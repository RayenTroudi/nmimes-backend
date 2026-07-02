alter table parents enable row level security;
alter table students enable row level security;
alter table homework_sessions enable row level security;
alter table session_steps enable row level security;
alter table teach_it_back_attempts enable row level security;

-- parents: a parent can only see/modify their own row
create policy parents_self_select on parents
  for select using (auth.uid() = id);
create policy parents_self_update on parents
  for update using (auth.uid() = id);
create policy parents_self_insert on parents
  for insert with check (auth.uid() = id);

-- students: owned via parent_id
create policy students_owner_select on students
  for select using (
    exists (select 1 from parents p where p.id = students.parent_id and p.id = auth.uid())
  );
create policy students_owner_all on students
  for all using (
    exists (select 1 from parents p where p.id = students.parent_id and p.id = auth.uid())
  ) with check (
    exists (select 1 from parents p where p.id = students.parent_id and p.id = auth.uid())
  );

-- homework_sessions: owned via students.parent_id
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

-- session_steps: owned via homework_sessions -> students.parent_id
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

-- teach_it_back_attempts: owned via homework_sessions -> students.parent_id
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
