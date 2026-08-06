-- supabase/migrations/20260806150036_decouple_progress_chapter_ids.sql
--
-- Decouple challenge progress from the seeded curriculum_chapters table.
--
-- The app's playable chapters live in the hardcoded MathCurriculum (7-entiers,
-- 7-fractions, 7-proportionnalite, ...), NOT in curriculum_chapters, which only
-- holds a few remote demo chapters. The original challenge_progress migration
-- FK'd chapter_id to curriculum_chapters and record_challenge_run raised
-- 'invalid_chapter' for any id not found there — which rejected every real run
-- (HTTP 400) and, even without the check, the FKs would have blocked the
-- inserts. chapter_id is just an opaque label for whatever chapter was played,
-- so drop the FKs and reduce the guard to a non-empty check.

alter table student_chapter_progress drop constraint if exists student_chapter_progress_chapter_id_fkey;
alter table topic_stats             drop constraint if exists topic_stats_chapter_id_fkey;
alter table challenge_runs          drop constraint if exists challenge_runs_chapter_id_fkey;

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
  -- chapter_id is an app-defined label; only reject an empty one.
  if p_chapter_id is null or length(trim(p_chapter_id)) = 0 then
    raise exception 'invalid_chapter';
  end if;

  p_total       := greatest(0, coalesce(p_total, 0));
  p_solved      := greatest(0, least(coalesce(p_solved, 0), p_total));
  p_attempted   := greatest(0, coalesce(p_attempted, 0));
  p_correct     := greatest(0, least(coalesce(p_correct, 0), p_attempted));
  p_best_streak := greatest(0, coalesce(p_best_streak, 0));
  p_passed      := coalesce(p_passed, false);

  v_score := p_solved * 10 + p_best_streak * 3;

  select (passed_at is not null) into v_already_passed
    from student_chapter_progress
   where student_id = v_student_id and chapter_id = p_chapter_id;
  v_already_passed := coalesce(v_already_passed, false);

  if p_passed and not v_already_passed then
    v_points      := 50 + p_solved * 5 + p_best_streak * 3;
    v_first_clear := true;
  end if;

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
    perform set_config('app.allow_points_write', '1', true);
    update students
       set points_balance = points_balance + v_points,
           updated_at      = now()
     where id = v_student_id;
    perform set_config('app.allow_points_write', '0', true);
  end if;

  return jsonb_build_object(
    'points_awarded', v_points,
    'first_clear',    v_first_clear,
    'new_balance',    (select points_balance from students where id = v_student_id)
  );
end;
$$;

revoke execute on function record_challenge_run(text, integer, integer, integer, integer, integer, boolean) from public;
revoke execute on function record_challenge_run(text, integer, integer, integer, integer, integer, boolean) from anon;
grant  execute on function record_challenge_run(text, integer, integer, integer, integer, integer, boolean) to authenticated;
