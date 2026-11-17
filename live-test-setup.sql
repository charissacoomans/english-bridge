-- English Bridge Live Test Portal database setup
-- Run once in Supabase > SQL Editor > New query.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  teacher_email text,
  created_at timestamptz not null default now()
);

create table if not exists public.test_sessions (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references auth.users(id) on delete cascade,
  teacher_email text not null,
  status text not null default 'in_progress' check (status in ('in_progress','completed')),
  answers jsonb not null default '{}'::jsonb,
  answered_count integer not null default 0 check (answered_count between 0 and 20),
  total_questions integer not null default 20 check (total_questions = 20),
  score integer,
  percent integer,
  level text,
  feedback jsonb,
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz
);

create or replace function public.handle_english_bridge_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles(id,full_name,email,teacher_email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name',''),
    lower(new.email),
    lower(coalesce(new.raw_user_meta_data ->> 'teacher_email',''))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_english_bridge_user_created on auth.users;
create trigger on_english_bridge_user_created
after insert on auth.users
for each row execute procedure public.handle_english_bridge_user();

alter table public.profiles enable row level security;
alter table public.test_sessions enable row level security;

drop policy if exists "profile owner or assigned teacher reads profile" on public.profiles;
create policy "profile owner or assigned teacher reads profile"
on public.profiles for select to authenticated
using (
  id = (select auth.uid())
  or (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'teacher'
    and teacher_email = lower((select auth.jwt() ->> 'email'))
  )
);

drop policy if exists "student creates own test session" on public.test_sessions;
create policy "student creates own test session"
on public.test_sessions for insert to authenticated
with check (
  student_id = (select auth.uid())
  and status = 'in_progress'
  and teacher_email = (
    select lower(p.teacher_email) from public.profiles p
    where p.id = (select auth.uid())
  )
);

drop policy if exists "student updates own active session" on public.test_sessions;
create policy "student updates own active session"
on public.test_sessions for update to authenticated
using (student_id = (select auth.uid()) and status = 'in_progress')
with check (
  student_id = (select auth.uid())
  and teacher_email = (
    select lower(p.teacher_email) from public.profiles p
    where p.id = (select auth.uid())
  )
  and status in ('in_progress','completed')
);

drop policy if exists "student or assigned teacher reads session" on public.test_sessions;
create policy "student or assigned teacher reads session"
on public.test_sessions for select to authenticated
using (
  student_id = (select auth.uid())
  or (
    (select auth.jwt() -> 'app_metadata' ->> 'role') = 'teacher'
    and teacher_email = lower((select auth.jwt() ->> 'email'))
  )
);

-- Protect the ownership and teacher link from being changed by the client.
create or replace function public.guard_english_bridge_session()
returns trigger language plpgsql
as $$
begin
  if old.student_id <> new.student_id or old.teacher_email <> new.teacher_email then
    raise exception 'Session ownership cannot be changed';
  end if;
  if old.status = 'completed' then
    raise exception 'Completed sessions cannot be changed';
  end if;
  if new.status not in ('in_progress','completed') then
    raise exception 'Invalid test session status';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_english_bridge_session_update on public.test_sessions;
create trigger guard_english_bridge_session_update
before update on public.test_sessions
for each row execute procedure public.guard_english_bridge_session();

-- Enable Supabase Realtime for the live monitor, only once.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'test_sessions'
  ) then
    alter publication supabase_realtime add table public.test_sessions;
  end if;
end $$;

-- After YOU register as the teacher, run this separately and replace the email:
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"teacher"}'::jsonb
-- where lower(email) = lower('YOUR-TEACHER-EMAIL@example.com');
-- Then sign out and sign in again so the role is included in your session token.
--
-- Never put the service_role secret in the website. The client uses only the
-- public publishable/anon key and the database is protected by RLS.