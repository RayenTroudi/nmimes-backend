create extension if not exists pgcrypto;

create table if not exists parents (
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

create table if not exists students (
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

create table if not exists homework_sessions (
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

create table if not exists session_steps (
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

create table if not exists teach_it_back_attempts (
  id             uuid primary key default gen_random_uuid(),
  session_id     uuid not null references homework_sessions(id) on delete cascade,
  transcript     text not null,
  clarity_score  integer not null check (clarity_score between 0 and 100),
  feedback       text,
  strengths      jsonb not null default '[]',
  gaps           jsonb not null default '[]',
  created_at     timestamptz not null default now()
);

create index if not exists idx_students_parent_id on students(parent_id);
create index if not exists idx_homework_sessions_student_id on homework_sessions(student_id);
create index if not exists idx_homework_sessions_status_created_at on homework_sessions(status, created_at);
create index if not exists idx_session_steps_session_id on session_steps(session_id);
create index if not exists idx_teach_it_back_attempts_session_id on teach_it_back_attempts(session_id);
