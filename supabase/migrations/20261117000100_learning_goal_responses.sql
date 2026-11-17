-- Learning goals questionnaire responses for English Bridge students.
-- Applied to the hosted project before this migration file was committed.
create table if not exists public.learning_goal_responses (
  student_id uuid primary key references auth.users(id) on delete cascade,
  teacher_email text not null,
  responses jsonb not null default '{}'::jsonb,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists learning_goal_responses_teacher_email_idx
  on public.learning_goal_responses (lower(teacher_email));
alter table public.learning_goal_responses enable row level security;
revoke all on table public.learning_goal_responses from anon, authenticated;
grant select, insert, update on table public.learning_goal_responses to authenticated;
drop policy if exists "Students read own learning goals" on public.learning_goal_responses;
create policy "Students read own learning goals"
on public.learning_goal_responses for select to authenticated
using ((select auth.uid()) = student_id);
drop policy if exists "Assigned teachers read learning goals" on public.learning_goal_responses;
create policy "Assigned teachers read learning goals"
on public.learning_goal_responses for select to authenticated
using (
  (select auth.jwt() -> 'app_metadata' ->> 'role') = 'teacher'
  and lower((select auth.jwt() ->> 'email')) = lower(teacher_email)
);
drop policy if exists "Students insert own learning goals" on public.learning_goal_responses;
create policy "Students insert own learning goals"
on public.learning_goal_responses for insert to authenticated
with check (
  (select auth.uid()) = student_id
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and lower(p.teacher_email) = lower(learning_goal_responses.teacher_email)
  )
);
drop policy if exists "Students update own learning goals" on public.learning_goal_responses;
create policy "Students update own learning goals"
on public.learning_goal_responses for update to authenticated
using ((select auth.uid()) = student_id)
with check (
  (select auth.uid()) = student_id
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and lower(p.teacher_email) = lower(learning_goal_responses.teacher_email)
  )
);
