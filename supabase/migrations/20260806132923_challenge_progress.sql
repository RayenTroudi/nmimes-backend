-- supabase/migrations/20260806132923_challenge_progress.sql
--
-- Persists each student's challenge advancement and the points they earn from
-- playing. Three tables plus one security-definer RPC that the app calls once
-- at the end of a challenge run. All progress writes go through the RPC so the
-- points formula and the "first clear only" rule stay authoritative on the
-- server; the client only reports what happened, never what it is worth.
--
-- Identity model (already established by earlier migrations):
--   * a student session's auth.uid() == students.id
--   * a parent  session's auth.uid() == parents.id, and their children are the
--     students rows whose parent_id = auth.uid().

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One row per (student, chapter): the map's "you are here" + best results.
create table if not exists student_chapter_progress (
  student_id   uuid    not null references students(id) on delete cascade,
  chapter_id   text    not null references curriculum_chapters(id),
  passed_at    timestamptz,                       -- set once on first pass, never cleared
  best_score   integer not null default 0,
  best_streak  integer not null default 0,
  times_played integer not null default 0,
  updated_at   timestamptz not null default now(),
  primary key (student_id, chapter_id)
);

-- One row per (student, chapter): answer history feeding the parent
-- "struggling topics" card. Counts wrong/timeout answers too.
create table if not exists topic_stats (
  student_id      uuid    not null references students(id) on delete cascade,
  chapter_id      text    not null references curriculum_chapters(id),
  attempted       integer not null default 0,
  correct         integer not null default 0,
  last_attempt_at timestamptz not null default now(),
  primary key (student_id, chapter_id)
);

-- Append-only log: one row per completed run. The literal register of each
-- student's advancement, and the source for any future history/streak views.
create table if not exists challenge_runs (
  id             uuid primary key default gen_random_uuid(),
  student_id     uuid    not null references students(id) on delete cascade,
  chapter_id     text    not null references curriculum_chapters(id),
  solved         integer not null,
  total          integer not null,
  best_streak    integer not null default 0,
  passed         boolean not null,
  points_awarded integer not null default 0,
  created_at     timestamptz not null default now()
);

create index if not exists challenge_runs_student_idx
  on challenge_runs(student_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Row Level Security
--
-- Reads: a student sees only their own rows; a parent sees only their
-- children's. There are deliberately NO insert/update/delete policies — every
-- write goes through record_challenge_run(), which runs as the definer and so
-- is not bound by these read-only policies.
-- ---------------------------------------------------------------------------

alter table student_chapter_progress enable row level security;
alter table topic_stats             enable row level security;
alter table challenge_runs          enable row level security;

drop policy if exists scp_select_own_or_child on student_chapter_progress;
create policy scp_select_own_or_child on student_chapter_progress
  for select using (
    student_id = auth.uid()
    or student_id in (select id from students where parent_id = auth.uid())
  );

drop policy if exists topic_stats_select_own_or_child on topic_stats;
create policy topic_stats_select_own_or_child on topic_stats
  for select using (
    student_id = auth.uid()
    or student_id in (select id from students where parent_id = auth.uid())
  );

drop policy if exists challenge_runs_select_own_or_child on challenge_runs;
create policy challenge_runs_select_own_or_child on challenge_runs
  for select using (
    student_id = auth.uid()
    or student_id in (select id from students where parent_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- RPC: record_challenge_run
--
-- Called by the child's app at the end of a chapter run. The student is
-- derived from auth.uid() (a student can never write for another student).
-- Idempotency: points are awarded only on the FIRST time a chapter is passed;
-- replays record the run and stats but earn 0. The points value scales with
-- performance and is computed here, so the client cannot inflate it.
-- ---------------------------------------------------------------------------

create or replace function record_challenge_run(
  p_chapter_id  text,
  p_solved      integer,
  p_total       integer,
  p_best_streak integer,
  p_attempted   integer,
  p_correct     integer,
  p_passed      boolean
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id     uuid := auth.uid();
  v_already_passed boolean;
  v_score          integer;
  v_points         integer := 0;
  v_first_clear    boolean := false;
begin
  if v_student_id is null
     or not exists (select 1 from students where id = v_student_id) then
    raise exception 'not_authenticated';
  end if;
  if not exists (select 1 from curriculum_chapters where id = p_chapter_id) then
    raise exception 'invalid_chapter';
  end if;

  -- Defensive clamps so a malformed client payload can never corrupt a row.
  p_total       := greatest(0, coalesce(p_total, 0));
  p_solved      := greatest(0, least(coalesce(p_solved, 0), p_total));
  p_attempted   := greatest(0, coalesce(p_attempted, 0));
  p_correct     := greatest(0, least(coalesce(p_correct, 0), p_attempted));
  p_best_streak := greatest(0, coalesce(p_best_streak, 0));
  p_passed      := coalesce(p_passed, false);

  -- Canonical run score (server owns the formula).
  v_score := p_solved * 10 + p_best_streak * 3;

  select (passed_at is not null) into v_already_passed
    from student_chapter_progress
   where student_id = v_student_id and chapter_id = p_chapter_id;
  v_already_passed := coalesce(v_already_passed, false);

  -- Performance-based points, first clear only.
  if p_passed and not v_already_passed then
    v_points      := 50 + p_solved * 5 + p_best_streak * 3;
    v_first_clear := true;
  end if;

  -- Chapter progress: passed_at is set once and never cleared; bests only grow.
  insert into student_chapter_progress as scp
    (student_id, chapter_id, passed_at, best_score, best_streak, times_played, updated_at)
  values
    (v_student_id, p_chapter_id,
     case when p_passed then now() end,
     v_score, p_best_streak, 1, now())
  on conflict (student_id, chapter_id) do update set
    passed_at    = coalesce(scp.passed_at, case when p_passed then now() end),
    best_score   = greatest(scp.best_score, excluded.best_score),
    best_streak  = greatest(scp.best_streak, excluded.best_streak),
    times_played = scp.times_played + 1,
    updated_at   = now();

  -- Topic stats: accumulate every answer, right or wrong.
  insert into topic_stats as ts
    (student_id, chapter_id, attempted, correct, last_attempt_at)
  values
    (v_student_id, p_chapter_id, p_attempted, p_correct, now())
  on conflict (student_id, chapter_id) do update set
    attempted       = ts.attempted + excluded.attempted,
    correct         = ts.correct + excluded.correct,
    last_attempt_at = now();

  insert into challenge_runs
    (student_id, chapter_id, solved, total, best_streak, passed, points_awarded)
  values
    (v_student_id, p_chapter_id, p_solved, p_total, p_best_streak, p_passed, v_points);

  if v_points > 0 then
    update students
       set points_balance = points_balance + v_points,
           updated_at      = now()
     where id = v_student_id;
  end if;

  return jsonb_build_object(
    'points_awarded', v_points,
    'first_clear',    v_first_clear,
    'new_balance',    (select points_balance from students where id = v_student_id)
  );
end;
$$;

-- Functions grant EXECUTE to PUBLIC by default; revoke it (and anon) so only a
-- signed-in student can reach the RPC. It rejects unauthenticated callers
-- internally too, but this keeps it off the anon REST surface entirely.
revoke execute on function record_challenge_run(text, integer, integer, integer, integer, integer, boolean) from public;
revoke execute on function record_challenge_run(text, integer, integer, integer, integer, integer, boolean) from anon;
grant  execute on function record_challenge_run(text, integer, integer, integer, integer, integer, boolean) to authenticated;
