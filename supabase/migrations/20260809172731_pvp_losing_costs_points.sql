-- Losing a match now costs 50 points instead of paying 50.
--
-- That inverts the assumption the payout migration was built on. Finishing paid
-- a floor of 50 immediately because the first player to report cannot yet know
-- the outcome, and a floor was safe when every later adjustment could only add.
-- With a penalty in play, paying the floor first would mean showing a winner
-- "+50" and then taking 100 away — so the floor is gone.
--
-- What replaces it uses the race rule: under it you cannot reach the end of the
-- set unless nobody got there before you, because whoever finishes first stops
-- everyone else. So a player reporting a completed run while the opponent has
-- not reported at all *is* the winner, and can be paid the win immediately.
-- Anyone else waits for settlement — which is the losing side, and holding a
-- deduction back a few seconds is the right way round to be wrong.

-- The payout table. Only the losing line changes.
create or replace function public.pvp_payout(p_result text)
returns integer
language sql
immutable
set search_path to 'public'
as $$
  select case p_result
           when 'won'  then 300
           when 'draw' then 100
           else             -50
         end;
$$;

-- Move a balance and report what actually moved.
--
-- NOTE: this version's write is silently reverted by the points-award gate and
-- is corrected by 20260809173203_pvp_credit_through_points_award_gate.sql. Kept
-- as applied so a replay reproduces the deployed history.
create or replace function public.pvp_credit(p_student uuid, p_delta integer)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_balance integer;
  v_applied integer;
begin
  if p_delta = 0 then
    return 0;
  end if;

  select points_balance into v_balance from students where id = p_student for update;
  if v_balance is null then
    return 0;
  end if;

  -- A penalty never takes more than the child has: a negative points balance is
  -- not something this app should be able to show. Clamping here rather than at
  -- the display keeps the ledger honest — awarded_a/awarded_b then record what
  -- was really applied, so a later settlement does not chase the shortfall.
  v_applied := greatest(p_delta, -v_balance);
  if v_applied = 0 then
    return 0;
  end if;

  update students set points_balance = points_balance + v_applied
   where id = p_student;

  return v_applied;
end;
$$;

-- Settlement pays the difference between what a side is owed and what it has
-- already had, in whichever direction that falls.
create or replace function public.pvp_settle(
  p_match_id uuid,
  p_force    boolean default false
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
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
    pvp_payout(case v_winner when 'a' then 'won' when 'draw' then 'draw' else 'lost' end)
      - v_m.awarded_a);

  v_applied_b := pvp_credit(
    v_m.player_b,
    pvp_payout(case v_winner when 'b' then 'won' when 'draw' then 'draw' else 'lost' end)
      - v_m.awarded_b);

  update pvp_matches
     set awarded_a  = awarded_a + v_applied_a,
         awarded_b  = awarded_b + v_applied_b,
         settled_at = coalesce(settled_at, now())
   where id = p_match_id;
end;
$$;

create or replace function public.pvp_report_result(
  p_match_id  uuid,
  p_score     integer,
  p_completed boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_me          uuid := auth.uid();
  v_m           pvp_matches%rowtype;
  v_is_a        boolean;
  v_before      integer;
  v_after       integer;
  v_balance     integer;
  v_their_score integer;
  v_applied     integer;
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

  -- Record the run. First report wins: a retry must not overwrite what was
  -- actually played.
  if v_is_a then
    update pvp_matches
       set score_a       = coalesce(score_a, greatest(p_score, 0)),
           completed_a   = coalesce(completed_a, p_completed),
           finished_a_at = coalesce(finished_a_at, now())
     where id = p_match_id;
  else
    update pvp_matches
       set score_b       = coalesce(score_b, greatest(p_score, 0)),
           completed_b   = coalesce(completed_b, p_completed),
           finished_b_at = coalesce(finished_b_at, now())
     where id = p_match_id;
  end if;

  -- Completing while the opponent has not reported is winning: the race rule
  -- means nobody can have got there first. Paying it now is what puts the win
  -- on the winner's results screen, which they are looking at this second.
  if v_before = 0 and p_completed and v_their_score is null then
    v_applied := pvp_credit(v_me, pvp_payout('won'));
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
$$;

-- CREATE OR REPLACE re-applies the schema's default privileges, so every
-- lock down has to be repeated alongside it.
revoke all on function public.pvp_report_result(uuid, integer, boolean)
  from public, anon;
grant execute on function public.pvp_report_result(uuid, integer, boolean)
  to authenticated, service_role;

revoke all on function public.pvp_payout(text)
  from public, anon, authenticated, service_role;
revoke all on function public.pvp_credit(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.pvp_settle(uuid, boolean)
  from public, anon, authenticated, service_role;
