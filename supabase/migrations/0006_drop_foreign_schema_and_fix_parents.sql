-- Removes a pre-existing, unrelated schema found on this project (quiz_responses,
-- step_responses, leaderboard_events, learning_gaps, teach_it_back, and an
-- incompatible `parents` table with full_name/notification_preferences instead of
-- this project's first_name/last_name/stripe_customer_id shape), confirmed
-- disposable by the project owner, then recreates `parents` with the correct schema.

drop function if exists uid_owns_step();
drop function if exists uid_owns_session();
drop function if exists uid_is_parent_of_student();
drop function if exists uid_is_parent_via_step();
drop function if exists uid_is_parent_via_session();

drop table if exists step_responses cascade;
drop table if exists quiz_responses cascade;
drop table if exists leaderboard_events cascade;
drop table if exists learning_gaps cascade;
drop table if exists teach_it_back cascade;

drop table if exists parents cascade;

create table parents (
  id                    uuid primary key references auth.users(id) on delete cascade,
  first_name            text not null,
  last_name             text not null,
  email                 text not null,
  stripe_customer_id    text unique,
  subscription_status   text not null default 'free'
    check (subscription_status in ('free', 'active', 'canceled', 'past_due')),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

drop trigger if exists trg_parents_updated_at on parents;
create trigger trg_parents_updated_at
  before update on parents
  for each row execute function set_updated_at();

alter table parents enable row level security;

create policy parents_self_select on parents
  for select using (auth.uid() = id);
create policy parents_self_update on parents
  for update using (auth.uid() = id);
create policy parents_self_insert on parents
  for insert with check (auth.uid() = id);

-- students/homework_sessions/session_steps/teach_it_back_attempts already reference
-- parents(id) via foreign keys created in 0001; dropping and recreating `parents`
-- with `cascade` above also drops those FK constraints, so restore them here.
alter table students
  add constraint students_parent_id_fkey
  foreign key (parent_id) references parents(id) on delete cascade;

-- re-apply RLS policies on students/homework_sessions/session_steps/teach_it_back_attempts
-- that referenced the dropped parents table (cascade drop removes policies depending on it)
drop policy if exists students_owner_select on students;
create policy students_owner_select on students
  for select using (
    exists (select 1 from parents p where p.id = students.parent_id and p.id = auth.uid())
  );

drop policy if exists students_owner_all on students;
create policy students_owner_all on students
  for all using (
    exists (select 1 from parents p where p.id = students.parent_id and p.id = auth.uid())
  ) with check (
    exists (select 1 from parents p where p.id = students.parent_id and p.id = auth.uid())
  );

drop policy if exists homework_sessions_owner_all on homework_sessions;
create policy homework_sessions_owner_all on homework_sessions
  for all using (
    exists (
      select 1 from students s
      join parents p on p.id = s.parent_id
      where s.id = homework_sessions.student_id and p.id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from students s
      join parents p on p.id = s.parent_id
      where s.id = homework_sessions.student_id and p.id = auth.uid()
    )
  );

drop policy if exists session_steps_owner_all on session_steps;
create policy session_steps_owner_all on session_steps
  for all using (
    exists (
      select 1 from homework_sessions hs
      join students s on s.id = hs.student_id
      join parents p on p.id = s.parent_id
      where hs.id = session_steps.session_id and p.id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from homework_sessions hs
      join students s on s.id = hs.student_id
      join parents p on p.id = s.parent_id
      where hs.id = session_steps.session_id and p.id = auth.uid()
    )
  );

drop policy if exists teach_it_back_attempts_owner_all on teach_it_back_attempts;
create policy teach_it_back_attempts_owner_all on teach_it_back_attempts
  for all using (
    exists (
      select 1 from homework_sessions hs
      join students s on s.id = hs.student_id
      join parents p on p.id = s.parent_id
      where hs.id = teach_it_back_attempts.session_id and p.id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from homework_sessions hs
      join students s on s.id = hs.student_id
      join parents p on p.id = s.parent_id
      where hs.id = teach_it_back_attempts.session_id and p.id = auth.uid()
    )
  );

select pg_notify('pgrst', 'reload schema');
