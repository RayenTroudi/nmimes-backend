-- supabase/migrations/20260821120000_avatar_perk_payout.sql
--
-- The award half of the avatar skills: Percent Gain (+25 %), Momentum and
-- Geometric Streak (+10 %) actually pay.
--
-- Written against the LIVE function bodies, dumped with pg_get_functiondef on
-- 2026-08-21, not against this repo's older copies — the deployed
-- pvp_report_result was well ahead of what was committed here, and rebuilding
-- it from the repo would have silently thrown away pvp_credit/pvp_settle.
--
-- Why the multiplier is not simply applied where points are added:
--   pvp_settle computes each player's TARGET payout and credits
--   `target - awarded_x`, so it converges rather than accumulating. Scaling a
--   delta there would fight itself every time the match settled again. The
--   multiplier therefore belongs on the target, and the "did they press it"
--   flag has to live on the match row — a function argument cannot reach
--   pvp_settle, which is also called from pvp_sweep_stale and from the
--   opponent's own report.
--
-- Why the old signatures survive as wrappers:
--   A build already on a phone calls the 3-argument pvp_report_result and the
--   7-argument record_challenge_run. Dropping those would break it. Each keeps
--   its arity and delegates to the new one with p_perk_used => false, so there
--   is one body per function and no overload ambiguity: an N-argument call
--   matches the N-argument function exactly.

-- Which player pressed their skill. Nullable, like completed_a/completed_b,
-- so "first report wins" is a coalesce rather than a special case.
alter table public.pvp_matches
  add column if not exists perk_used_a boolean,
  add column if not exists perk_used_b boolean;

-- What a result is worth to this player, with their avatar's multiplier
-- applied only to a positive award.
--
-- A loss pays -50. Multiplying a penalty would turn a bought perk into a
-- punishment, so the guard is on the sign, not on the perk.
create or replace function public.pvp_target_payout(
  p_student   uuid,
  p_result    text,
  p_perk_used boolean
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select case
           when coalesce(p_perk_used, false) and pvp_payout(p_result) > 0
           then floor(
                  pvp_payout(p_result)
                  * coalesce(avatar_payout_multiplier(p_student), 1.0)
                )::integer
           else pvp_payout(p_result)
         end;
$$;

revoke all on function public.pvp_target_payout(uuid, text, boolean) from public, anon, authenticated;

-- Settlement, unchanged except that each side's target now runs through
-- pvp_target_payout with the flag recorded on the row.
create or replace function public.pvp_settle(p_match_id uuid, p_force boolean default false)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_m         pvp_matches%rowtype;
  v_winner    text;
  v_applied_a integer;
  v_applied_b integer;
begin
  select * into v_m from pvp_matches where id = p_match_id for update;
  if v_m.id is null then
    return;
  end if;

  -- A match nobody reported is not a 0-0 draw worth 100 each, even under force.
  if v_m.score_a is null and v_m.score_b is null then
    return;
  end if;

  if not p_force and (v_m.score_a is null or v_m.score_b is null) then
    return;
  end if;

  v_winner := pvp_winner(p_match_id);

  v_applied_a := pvp_credit(
    v_m.player_a,
    pvp_target_payout(
      v_m.player_a,
      case v_winner when 'a' then 'won' when 'draw' then 'draw' else 'lost' end,
      v_m.perk_used_a)
      - v_m.awarded_a);

  v_applied_b := pvp_credit(
    v_m.player_b,
    pvp_target_payout(
      v_m.player_b,
      case v_winner when 'b' then 'won' when 'draw' then 'draw' else 'lost' end,
      v_m.perk_used_b)
      - v_m.awarded_b);

  update pvp_matches
     set awarded_a  = awarded_a + v_applied_a,
         awarded_b  = awarded_b + v_applied_b,
         settled_at = coalesce(settled_at, now())
   where id = p_match_id;
end;
$function$;

-- The reporting path, unchanged except that it records the flag and pays the
-- early "completed first" win through pvp_target_payout.
create or replace function public.pvp_report_result(
  p_match_id  uuid,
  p_score     integer,
  p_completed boolean,
  p_perk_used boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me            uuid := auth.uid();
  v_m             pvp_matches%rowtype;
  v_is_a          boolean;
  v_before        integer;
  v_after         integer;
  v_balance       integer;
  v_their_score   integer;
  v_applied       integer;
  v_perk_used     boolean;
begin
  select * into v_m from pvp_matches where id = p_match_id for update;
  if v_m.id is null then
    raise exception 'unknown_match';
  end if;
  if v_me is null or v_me not in (v_m.player_a, v_m.player_b) then
    raise exception 'not_a_participant';
  end if;

  v_is_a        := (v_m.player_a = v_me);
  v_before      := case when v_is_a then v_m.awarded_a else v_m.awarded_b end;
  v_their_score := case when v_is_a then v_m.score_b  else v_m.score_a  end;

  -- First report wins here too: a retry cannot add a skill that was not
  -- pressed, nor take one back.
  v_perk_used := coalesce(
    case when v_is_a then v_m.perk_used_a else v_m.perk_used_b end,
    p_perk_used);

  -- Record the run. First report wins: a retry must not overwrite what was
  -- actually played.
  if v_is_a then
    update pvp_matches
       set score_a       = coalesce(score_a, greatest(p_score, 0)),
           completed_a   = coalesce(completed_a, p_completed),
           perk_used_a   = coalesce(perk_used_a, p_perk_used),
           finished_a_at = coalesce(finished_a_at, now())
     where id = p_match_id;
  else
    update pvp_matches
       set score_b       = coalesce(score_b, greatest(p_score, 0)),
           completed_b   = coalesce(completed_b, p_completed),
           perk_used_b   = coalesce(perk_used_b, p_perk_used),
           finished_b_at = coalesce(finished_b_at, now())
     where id = p_match_id;
  end if;

  -- Completing while the opponent has not reported is winning: the race rule
  -- means nobody can have got there first. Paying it now is what puts the win
  -- on the winner's results screen, which they are looking at this second.
  if v_before = 0 and p_completed and v_their_score is null then
    v_applied := pvp_credit(v_me, pvp_target_payout(v_me, 'won', v_perk_used));
    if v_is_a then
      update pvp_matches set awarded_a = awarded_a + v_applied where id = p_match_id;
    else
      update pvp_matches set awarded_b = awarded_b + v_applied where id = p_match_id;
    end if;
  end if;

  -- Both sides in? Then the outcome is known and both are settled to it.
  perform pvp_settle(p_match_id);

  -- Settle anything this player was left hanging on by an opponent who left.
  perform pvp_sweep_stale(v_me);

  select case when v_is_a then awarded_a else awarded_b end
    into v_after
    from pvp_matches
   where id = p_match_id;

  select points_balance into v_balance from students where id = v_me;

  return jsonb_build_object(
    -- What *this call* moved, in whichever direction. A retried report moves
    -- nothing and says so, rather than inviting the app to announce it twice.
    'points_awarded', v_after - v_before,
    'new_balance',    v_balance
  );
end;
$function$;

-- The 3-argument form an older build still calls: same arity, no skill.
create or replace function public.pvp_report_result(
  p_match_id  uuid,
  p_score     integer,
  p_completed boolean default false
)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  select public.pvp_report_result(p_match_id, p_score, p_completed, false);
$function$;

revoke all on function public.pvp_report_result(uuid, integer, boolean, boolean) from public, anon;
grant execute on function public.pvp_report_result(uuid, integer, boolean, boolean) to authenticated;

-- Solo runs. The award here really is one line, so the multiplier goes on it.
create or replace function public.record_challenge_run(
  p_chapter_id  text,
  p_solved      integer,
  p_total       integer,
  p_best_streak integer,
  p_attempted   integer,
  p_correct     integer,
  p_passed      boolean,
  p_perk_used   boolean
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
    -- Only ever scales a positive award, and only when the skill was pressed.
    if coalesce(p_perk_used, false) and v_points > 0 then
      v_points := floor(
        v_points * coalesce(avatar_payout_multiplier(v_student_id), 1.0)
      )::integer;
    end if;
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
$function$;

-- The 7-argument form an older build still calls: same arity, no skill.
create or replace function public.record_challenge_run(
  p_chapter_id  text,
  p_solved      integer,
  p_total       integer,
  p_best_streak integer,
  p_attempted   integer,
  p_correct     integer,
  p_passed      boolean
)
returns jsonb
language sql
security definer
set search_path to 'public'
as $function$
  select public.record_challenge_run(
    p_chapter_id, p_solved, p_total, p_best_streak,
    p_attempted, p_correct, p_passed, false);
$function$;

revoke all on function public.record_challenge_run(text, integer, integer, integer, integer, integer, boolean, boolean) from public, anon;
grant execute on function public.record_challenge_run(text, integer, integer, integer, integer, integer, boolean, boolean) to authenticated;
