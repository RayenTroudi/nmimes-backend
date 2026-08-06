-- supabase/migrations/0001_curriculum_content.sql

create table if not exists curriculum_chapters (
  id          text primary key,
  level       text not null check (level in ('7', '8', '9')),
  theme       text not null check (theme in ('numeric', 'geometric')),
  title       jsonb not null,
  subtitle    jsonb not null,
  icon        text not null,
  sort_order  integer not null,
  created_at  timestamptz not null default now()
);

create table if not exists curriculum_questions (
  id           uuid primary key default gen_random_uuid(),
  chapter_id   text not null references curriculum_chapters(id) on delete cascade,
  sort_order   integer not null,
  kind         text not null check (kind in (
    'mcq', 'true_false', 'input', 'multi_select',
    'drag_fill', 'sort_buckets', 'maze',
    'match_pairs', 'number_line'
  )),
  payload      jsonb not null,
  created_at   timestamptz not null default now()
);

create index if not exists curriculum_questions_chapter_idx
  on curriculum_questions(chapter_id, sort_order);

alter table curriculum_chapters enable row level security;
alter table curriculum_questions enable row level security;

drop policy if exists "curriculum_chapters_public_read" on curriculum_chapters;
create policy "curriculum_chapters_public_read" on curriculum_chapters
  for select using (true);

drop policy if exists "curriculum_questions_public_read" on curriculum_questions;
create policy "curriculum_questions_public_read" on curriculum_questions
  for select using (true);
