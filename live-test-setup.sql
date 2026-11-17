-- English Bridge Live Test Portal — consolidated database setup
-- Run in Supabase > SQL Editor > New query.
-- Safe to re-run for this project: creates missing objects and replaces named policies/triggers.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

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

create or replace function private.handle_english_bridge_user()
returns trigger
language plpgsql
security definer
set search_path = ''
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

revoke all on function private.handle_english_bridge_user() from public, anon, authenticated;
drop trigger if exists on_english_bridge_user_created on auth.users;
create trigger on_english_bridge_user_created
after insert on auth.users
for each row execute function private.handle_english_bridge_user();

alter table public.profiles enable row level security;
alter table public.test_sessions enable row level security;

grant select on public.profiles to authenticated;
grant select, insert, update on public.test_sessions to authenticated;
revoke all on public.profiles from anon;
revoke all on public.test_sessions from anon;

drop policy if exists "profile owner or assigned teacher reads profile" on public.profiles;
create policy "profile owner or assigned teacher reads profile"
on public.profiles for select to authenticated
using (
  id = (select auth.uid())
  or (
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'teacher'
    and teacher_email = lower(((select auth.jwt()) ->> 'email'))
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
    ((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'teacher'
    and teacher_email = lower(((select auth.jwt()) ->> 'email'))
  )
);

create or replace function private.grade_english_bridge_session()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  answer_key integer[] := array[1,0,0,1,1,1,2,0,1,1,1,0,1,1,1,1,1,1,2,1];
  explanations text[] := array[
    'With she, use is.',
    'Small is the opposite of big.',
    'Use the base verb with I.',
    'Use are with plural nouns.',
    'Shoes are worn on your feet.',
    'Yesterday signals the past simple: went.',
    'Use any in most negative sentences.',
    'Crowded means full of people.',
    'Use more + adjective for this comparison.',
    'Use since with a starting point in time.',
    'Second conditional: if + past simple, would + verb.',
    'Run into can mean meet by chance.',
    'Past perfect describes an earlier past event.',
    'Reported questions use statement word order.',
    'The passage says she now takes the train.',
    'Hardly at the beginning requires inversion.',
    'Substantial means significant.',
    'Use which in a non-defining relative clause.',
    'The findings challenge the assumption about longer lessons.',
    'Use wish + past perfect for regret about the past.'
  ];
  item record;
  idx integer;
  selected integer;
  calculated_score integer := 0;
  feedback_rows jsonb := '[]'::jsonb;
begin
  if tg_op = 'UPDATE' then
    if old.student_id <> new.student_id or old.teacher_email <> new.teacher_email then
      raise exception 'Session ownership cannot be changed';
    end if;
    if old.status = 'completed' then
      raise exception 'Completed sessions cannot be changed';
    end if;
  end if;

  if new.status not in ('in_progress','completed') then
    raise exception 'Invalid test session status';
  end if;

  new.answers := coalesce(new.answers, '{}'::jsonb);
  for item in select key, value from jsonb_each(new.answers)
  loop
    if item.key !~ '^(0|[1-9]|1[0-9])$'
       or (item.value::text !~ '^"[0-2]"$' and item.value::text !~ '^[0-2]$') then
      raise exception 'Invalid answer payload';
    end if;
  end loop;

  select count(*)::integer into new.answered_count
  from jsonb_each(new.answers);

  new.total_questions := 20;
  new.updated_at := now();

  if new.status = 'completed' then
    for idx in 0..19 loop
      if new.answers ? idx::text then
        selected := (new.answers ->> idx::text)::integer;
      else
        selected := -1;
      end if;

      if selected = answer_key[idx + 1] then
        calculated_score := calculated_score + 1;
      end if;

      feedback_rows := feedback_rows || jsonb_build_array(
        jsonb_build_object(
          'index', idx,
          'correct_choice', answer_key[idx + 1],
          'is_correct', selected = answer_key[idx + 1],
          'explanation', explanations[idx + 1]
        )
      );
    end loop;

    new.score := calculated_score;
    new.percent := round(calculated_score * 100.0 / 20)::integer;
    new.level := case
      when new.percent < 25 then 'Pre-A1'
      when new.percent < 45 then 'A1'
      when new.percent < 65 then 'A2'
      when new.percent < 85 then 'B1'
      else 'B2'
    end;
    new.feedback := feedback_rows;
    new.submitted_at := coalesce(new.submitted_at, now());
  else
    new.score := null;
    new.percent := null;
    new.level := null;
    new.feedback := null;
    new.submitted_at := null;
  end if;

  return new;
end;
$$;

revoke all on function private.grade_english_bridge_session() from public, anon, authenticated;
drop trigger if exists grade_english_bridge_session on public.test_sessions;
create trigger grade_english_bridge_session
before insert or update on public.test_sessions
for each row execute function private.grade_english_bridge_session();

create index if not exists test_sessions_student_started_idx
on public.test_sessions (student_id, started_at desc);
create index if not exists test_sessions_teacher_status_started_idx
on public.test_sessions (teacher_email, status, started_at desc);

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

-- After registering your own teacher account, run this separately with your email:
-- update auth.users
-- set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"teacher"}'::jsonb
-- where lower(email) = lower('YOUR-TEACHER-EMAIL@example.com');
-- Sign out and back in after promoting the teacher role.
--
-- Do not put the service_role/secret key in the website.
