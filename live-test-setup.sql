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

-- Enforce ownership and calculate the submitted score in the database.
-- A browser cannot simply submit a fabricated score value.
create or replace function public.guard_and_grade_english_bridge_session()
returns trigger language plpgsql
as $$
declare
  answer_key jsonb := '[1,0,0,1,1,1,2,0,1,1,1,0,1,1,1,1,1,1,2,1]'::jsonb;
  i integer;
  calculated_score integer := 0;
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
  new.answers := coalesce(new.answers, '{}'::jsonb);
  new.answered_count := least(jsonb_object_length(new.answers), 20);
  if new.status = 'completed' then
    for i in 0..19 loop
      if new.answers ? i::text
         and (new.answers ->> i::text) ~ '^[0-2]$'
         and (new.answers ->> i::text)::integer = (answer_key ->> i)::integer then
        calculated_score := calculated_score + 1;
      end if;
    end loop;
    new.total_questions := 20;
    new.score := calculated_score;
    new.percent := round(calculated_score * 100.0 / 20)::integer;
    new.level := case
      when new.percent < 25 then 'Pre-A1'
      when new.percent < 45 then 'A1'
      when new.percent < 65 then 'A2'
      when new.percent < 85 then 'B1'
      else 'B2'
    end;
    new.submitted_at := coalesce(new.submitted_at, now());
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists guard_english_bridge_session_update on public.test_sessions;
create trigger guard_english_bridge_session_update
before update on public.test_sessions
for each row execute procedure public.guard_and_grade_english_bridge_session();

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

-- After YOU register as teacher, run this separately with your email:
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"teacher"}'::jsonb
-- where lower(email) = lower('YOUR-TEACHER-EMAIL@example.com');
-- Then sign out and back in to refresh the session token.
--
-- Never put the service_role secret in the website.