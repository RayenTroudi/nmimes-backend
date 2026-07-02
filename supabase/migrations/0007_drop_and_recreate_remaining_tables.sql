-- The remaining tables (students, homework_sessions, session_steps,
-- teach_it_back_attempts) turned out to also be pre-existing foreign schema with
-- different columns than this project's spec (e.g. students had xp/streak_days
-- instead of points_balance/grade/interest). Confirmed disposable by the project
-- owner (all empty, no data loss) and dropped/recreated to match
-- docs/superpowers/specs/2026-07-02-supabase-schema-design.md exactly.

drop table if exists teach_it_back_attempts cascade;
drop table if exists session_steps cascade;
drop table if exists homework_sessions cascade;
drop table if exists students cascade;

create table students (
  id                 uuid primary key default gen_random_uuid(),
  parent_id          uuid not null references parents(id) on delete cascade,
  name               text not null,
  username           text,
  grade              text,
  interest           text,
  access_code_hash   text not null,
  points_balance     integer not null default 0,
  avatar_url         text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table homework_sessions (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references students(id) on delete cascade,
  ocr_text      text not null,
  image_url     text,
  subject       text,
  topic         text,
  status        text not null default 'active'
    check (status in ('active', 'completed', 'abandoned')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table session_steps (
  id               uuid primary key default gen_random_uuid(),
  session_id       uuid not null references homework_sessions(id) on delete cascade,
  step_number      integer not null,
  question         text not null,
  student_answer   text,
  tier             text
    check (tier in ('correct', 'partially_correct', 'incorrect', 'off_topic')),
  feedback         text,
  created_at       timestamptz not null default now()
);

create table teach_it_back_attempts (
  id             uuid primary key default gen_random_uuid(),
  session_id     uuid not null references homework_sessions(id) on delete cascade,
  transcript     text not null,
  clarity_score  integer not null check (clarity_score between 0 and 100),
  feedback       text,
  strengths      jsonb not null default '[]',
  gaps           jsonb not null default '[]',
  created_at     timestamptz not null default now()
);

create index idx_students_parent_id on students(parent_id);
create index idx_homework_sessions_student_id on homework_sessions(student_id);
create index idx_homework_sessions_status_created_at on homework_sessions(status, created_at);
create index idx_session_steps_session_id on session_steps(session_id);
create index idx_teach_it_back_attempts_session_id on teach_it_back_attempts(session_id);

drop trigger if exists trg_students_updated_at on students;
create trigger trg_students_updated_at
  before update on students
  for each row execute function set_updated_at();

drop trigger if exists trg_homework_sessions_updated_at on homework_sessions;
create trigger trg_homework_sessions_updated_at
  before update on homework_sessions
  for each row execute function set_updated_at();

alter table students enable row level security;
alter table homework_sessions enable row level security;
alter table session_steps enable row level security;
alter table teach_it_back_attempts enable row level security;

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
