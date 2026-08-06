-- supabase/migrations/20260720165930_students_as_independent_auth_users.sql
--
-- Backfilled from the live database. Turns students into first-class auth users:
-- a student's id IS their auth.users id, so a child signs in independently of
-- any parent session. Adds the username format check, the self read/update RLS
-- policies, and the anti-tamper trigger that stops a student changing their own
-- protected columns (parent_id, username, points_balance).

-- students.id becomes the auth user's id rather than a generated uuid.
alter table students alter column id drop default;

alter table students drop constraint if exists students_id_fkey;
alter table students
  add constraint students_id_fkey
  foreign key (id) references auth.users(id) on delete cascade;

alter table students drop constraint if exists students_username_format;
alter table students
  add constraint students_username_format
  check (username ~ '^[a-z0-9_]{3,20}$');

-- A student may read and update their own row…
drop policy if exists students_self_select on students;
create policy students_self_select on students
  for select using (auth.uid() = id);

drop policy if exists students_self_update on students;
create policy students_self_update on students
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- …but not tamper with protected columns on it. (record_challenge_run later
-- opens a transaction-local gate to award points through this guard; see
-- 20260806135223_points_award_gate.)
create or replace function public.protect_student_self_update()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() = new.id then
    new.parent_id      := old.parent_id;
    new.points_balance := old.points_balance;
    new.username       := old.username;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_student_self_update on students;
create trigger trg_protect_student_self_update
  before update on students
  for each row execute function public.protect_student_self_update();
