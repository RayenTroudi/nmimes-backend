-- PVP matches are a race, and the race pays into students.points_balance.
--
-- Two things were missing. Points: pvp_report_result recorded the score and
-- stopped, so winning earned nothing — the "Total Points" the app showed at the
-- end of a match was the in-run score, computed on the device and thrown away
-- with the screen. And the verdict: the winner was whoever solved more, but the
-- match is now decided at the finish line. The first player to get through the
-- whole set wins, and their opponent is stopped where they stand.
--
-- Running out of hearts is not finishing. Handing the win to whoever fails
-- first would make answering badly as fast as possible the winning strategy, so
-- an eliminated run ends only itself; the other player keeps going. With three
-- hearts over eight puzzles, completing the set already implies at least six
-- correct, so speed cannot be bought with sloppiness.
--
-- The payout is 300 for a win, 100 for a draw, 50 for a loss, credited once per
-- match ever. It lives here rather than in the client for the same reason the
-- record_challenge_run formula does: a child who can edit their reported score
-- must not thereby be able to edit their balance.
--
-- Timing is the awkward part. A match ends for each player separately, so the
-- one who finishes first reports while the opponent is still going and the
-- outcome is not yet knowable — but they are already looking at their results
-- screen. Rather than make them wait or pay them nothing, finishing pays the
-- floor (50) immediately, and settlement tops that up once both sides are in.
-- Awards only ever go up: a number a child has been shown is never taken back.

-- ── Ledger ──────────────────────────────────────────────────────────────────
-- Per-side running total on the match itself rather than a separate table:
-- "how much has this player been paid for this match" is a fact about the
-- match, and keeping it here makes the top-up a comparison instead of a join.
alter table pvp_matches
  add column if not exists awarded_a   integer not null default 0,
  add column if not exists awarded_b   integer not null default 0,
  -- Whether each side saw the set through, as opposed to running out of hearts.
  -- Null until that side reports, which is what "still playing" looks like.
  add column if not exists completed_a boolean,
  add column if not exists completed_b boolean,
  add column if not exists settled_at  timestamptz;

-- ── The payout table, stated once ───────────────────────────────────────────
create or replace function public.pvp_payout(p_result text)
returns integer
language sql
immutable
as $$
  select case p_result
           when 'won'  then 300
           when 'draw' then 100
           else              50
         end;
$$;

-- ── Who won ─────────────────────────────────────────────────────────────────
-- Returns 'a', 'b' or 'draw'. Completion decides it; the scores are only
-- consulted when neither player got to the end.
create or replace function public.pvp_winner(p_match_id uuid)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_m pvp_matches%rowtype;
  v_a boolean;
  v_b boolean;
begin
  select * into v_m from pvp_matches where id = p_match_id;
  if v_m.id is null then
    return 'draw';
  end if;

  -- A side that never reported did not complete.
  v_a := coalesce(v_m.completed_a, false);
  v_b := coalesce(v_m.completed_b, false);

  if v_a and not v_b then return 'a'; end if;
  if v_b and not v_a then return 'b'; end if;

  -- Both got there: the clock separates them. Equal to the microsecond is a
  -- genuine dead heat rather than a tie to be broken on score — they ran the
  -- same race and arrived together.
  if v_a and v_b then
    if v_m.finished_a_at < v_m.finished_b_at then return 'a'; end if;
    if v_m.finished_b_at < v_m.finished_a_at then return 'b'; end if;
    return 'draw';
  end if;

  -- Neither finished, so all there is to go on is how far each got.
  if coalesce(v_m.score_a, 0) > coalesce(v_m.score_b, 0) then return 'a'; end if;
  if coalesce(v_m.score_b, 0) > coalesce(v_m.score_a, 0) then return 'b'; end if;
  return 'draw';
end;
$$;

-- ── Settlement ──────────────────────────────────────────────────────────────
-- Pays both sides up to what the outcome is worth. Idempotent by construction:
-- it credits the difference between what a side is owed and what it has already
-- been paid, so calling it twice is free and calling it after a partial payment
-- finishes the job.
--
-- p_force settles a match one side abandoned, scoring the absentee 0.
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
  v_m        pvp_matches%rowtype;
  v_winner   text;
  v_target_a integer;
  v_target_b integer;
  v_delta    integer;
begin
  select * into v_m from pvp_matches where id = p_match_id for update;
  if v_m.id is null then
    return;
  end if;

  -- A match nobody reported is not a 0-0 draw worth 100 each, even under force.
  if v_m.score_a is null and v_m.score_b is null then
    return;
  end if;

  -- Otherwise the outcome is only known once both sides are in.
  if not p_force and (v_m.score_a is null or v_m.score_b is null) then
    return;
  end if;

  v_winner := pvp_winner(p_match_id);
  v_target_a := pvp_payout(case v_winner when 'a' then 'won'
                                         when 'draw' then 'draw'
                                         else 'lost' end);
  v_target_b := pvp_payout(case v_winner when 'b' then 'won'
                                         when 'draw' then 'draw'
                                         else 'lost' end);

  v_delta := greatest(v_target_a - v_m.awarded_a, 0);
  if v_delta > 0 then
    update students set points_balance = points_balance + v_delta
     where id = v_m.player_a;
  end if;

  v_delta := greatest(v_target_b - v_m.awarded_b, 0);
  if v_delta > 0 then
    update students set points_balance = points_balance + v_delta
     where id = v_m.player_b;
  end if;

  update pvp_matches
     set awarded_a  = greatest(v_target_a, awarded_a),
         awarded_b  = greatest(v_target_b, awarded_b),
         settled_at = coalesce(settled_at, now())
   where id = p_match_id;
end;
$$;

-- ── Abandoned matches ───────────────────────────────────────────────────────
-- An opponent who closes the app never reports, which would otherwise leave the
-- player who did finish stuck at the floor forever. Their next report sweeps
-- their own old matches and settles them as a forfeit.
--
-- Bounded and skip-locked: this runs on the tail of a child's match, not as a
-- maintenance job, and must never be the reason a result is slow to come back.
create or replace function public.pvp_sweep_stale(
  p_student uuid,
  p_grace   interval default interval '10 minutes'
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_id uuid;
begin
  for v_id in
    select id
      from pvp_matches
     where settled_at is null
       and created_at < now() - p_grace
       and (player_a = p_student or player_b = p_student)
       -- exactly one side reported
       and (score_a is null) <> (score_b is null)
     limit 20
     for update skip locked
  loop
    perform pvp_settle(v_id, true);
  end loop;
end;
$$;

-- ── Reporting ───────────────────────────────────────────────────────────────
-- Returns jsonb where it used to return void, so the app can show what the
-- match actually paid instead of implying the run score was credited, and takes
-- p_completed so the server can tell a finish from an elimination. Both changes
-- alter the signature, which is why this is a drop rather than a replace.
drop function if exists public.pvp_report_result(uuid, integer);

create function public.pvp_report_result(
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
  v_me      uuid := auth.uid();
  v_m       pvp_matches%rowtype;
  v_is_a    boolean;
  v_before  integer;
  v_after   integer;
  v_balance integer;
  v_floor   constant integer := 50;
begin
  select * into v_m from pvp_matches where id = p_match_id for update;
  if v_m.id is null then
    raise exception 'unknown_match';
  end if;
  if v_me is null or v_me not in (v_m.player_a, v_m.player_b) then
    raise exception 'not_a_participant';
  end if;

  v_is_a   := (v_m.player_a = v_me);
  v_before := case when v_is_a then v_m.awarded_a else v_m.awarded_b end;

  -- Record the run. First report wins, exactly as before: a retry must not
  -- overwrite what was actually played.
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

  -- Finishing pays the floor now, because the opponent may still be playing and
  -- the child is looking at their results screen at this moment. It is the
  -- smallest outcome, so settlement can only add to it.
  if v_before = 0 then
    update students set points_balance = points_balance + v_floor where id = v_me;
    if v_is_a then
      update pvp_matches set awarded_a = v_floor where id = p_match_id;
    else
      update pvp_matches set awarded_b = v_floor where id = p_match_id;
    end if;
  end if;

  -- Both sides in? Then the outcome is known and both are topped up to it.
  perform pvp_settle(p_match_id);

  -- Settle anything this player was left hanging on by an opponent who left.
  perform pvp_sweep_stale(v_me);

  select case when v_is_a then awarded_a else awarded_b end
    into v_after
    from pvp_matches
   where id = p_match_id;

  select points_balance into v_balance from students where id = v_me;

  return jsonb_build_object(
    -- What *this call* credited, so a retried report reports zero rather than
    -- inviting the app to announce the same reward twice.
    'points_awarded', greatest(v_after - v_before, 0),
    'new_balance',    v_balance
  );
end;
$$;

-- ── Grants ──────────────────────────────────────────────────────────────────
-- NOTE: these revokes are not sufficient on Supabase and are corrected by
-- 20260809171156_pvp_payout_lock_down_grants.sql. Revoking from PUBLIC leaves
-- the per-role EXECUTE that ALTER DEFAULT PRIVILEGES grants to anon,
-- authenticated and service_role on every new function in this schema. Kept as
-- applied so a replay from scratch reproduces the deployed history.
--
-- Restores the ACL the dropped function had. CREATE grants EXECUTE to PUBLIC by
-- default, which for a SECURITY DEFINER function in an API-exposed schema would
-- hand anon the ability to report results.
revoke all on function public.pvp_report_result(uuid, integer, boolean) from public;
grant execute on function public.pvp_report_result(uuid, integer, boolean)
  to authenticated, service_role;

-- The helpers are internals of the above. They are SECURITY DEFINER and take a
-- student or match id, so leaving them callable would let any signed-in child
-- settle any match — or credit someone else's balance.
revoke all on function public.pvp_payout(text) from public;
revoke all on function public.pvp_winner(uuid) from public;
revoke all on function public.pvp_settle(uuid, boolean) from public;
revoke all on function public.pvp_sweep_stale(uuid, interval) from public;
