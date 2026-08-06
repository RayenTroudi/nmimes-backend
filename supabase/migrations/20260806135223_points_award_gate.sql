-- supabase/migrations/20260806135223_points_award_gate.sql
--
-- `students.points_balance` is protected by trg_protect_student_self_update:
-- when a student updates their own row, the trigger reverts points_balance to
-- its old value, so a child can never award themselves points by writing to
-- their row directly. record_challenge_run also runs as the student (auth.uid()
-- == students.id), so that same guard was silently undoing the points it
-- awards.
--
-- Fix: a transaction-local gate, `app.allow_points_write`, that only a trusted
-- SECURITY DEFINER server function can open. The protect trigger still reverts
-- points on every ordinary self-update; it lets the change through only while
-- the gate is set. A student cannot set the gate — they can only call the RPCs
-- we define, and none of them open it except to apply a server-computed award.
-- parent_id and username stay protected unconditionally.

create or replace function public.protect_student_self_update()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() = new.id then
    -- Never changeable on a student's own row.
    new.parent_id := old.parent_id;
    new.username  := old.username;
    -- points_balance is protected too, EXCEPT while the sanctioned award gate
    -- is open (opened only by record_challenge_run, which computes the award
    -- itself). Any other self-update leaves the balance untouched.
    if coalesce(current_setting('app.allow_points_write', true), '') <> '1' then
      new.points_balance := old.points_balance;
    end if;
  end if;
  return new;
end;
$$;

-- Re-create record_challenge_run so it opens the gate right before crediting
-- points. Body is identical to 0005 apart from the single set_config line.
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
    -- Open the transaction-local gate so the protect trigger lets this
    -- server-computed award through. Resets automatically at transaction end.
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
