# PENDING: wire `avatar_payout_multiplier` into the two award RPCs

**This file is deliberately a `.md`, not a `.sql` — no migration runner picks it
up. Do not rename it to `.sql` and apply it as-is.**

## Why this is pending

`avatar_payout_multiplier(uuid)` exists (see
`20260820180000_avatar_perks.sql`) but nothing calls it yet. The two functions
that award points — `pvp_report_result` and `record_challenge_run` — need a
`p_perk_used` argument and a multiplier applied to the award, and that can't be
written safely right now:

The **live** `pvp_report_result` takes **three** arguments
(`p_match_id uuid, p_score integer, p_completed boolean`) and **returns the
reward as JSON**. The newest **committed** migration
(`20260808150000_pvp_live_match.sql` or wherever it was last touched) only
shows a **two-argument, `returns void`** version. That gap means the deployed
function has moved on since the last commit that touched it — this repo has no
Supabase CLI, `psql`, or any DB connection available to confirm the current
truth by hand (see the `supabase-deployed-by-hand` project memory: committed
migrations and the live database are known to diverge here, in both
directions). Recreating `pvp_report_result` from the committed source would
silently **revert whatever changed the live payout** between that commit and
now. `record_challenge_run`'s committed version looks current
(`20260806150036_decouple_progress_chapter_ids.sql`), but it shares the same
award-guard shape, so it's grouped into the same pending change for a single
coherent review.

## Step 1 — run this first, against the live database

```sql
select pg_get_functiondef(p.oid)
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'pvp_report_result';
```

Save the result verbatim into a migration of its own
(`<ts>_pvp_report_result_baseline.sql`), prefixed with a comment that it is a
transcription of the deployed function taken on the date it was pulled, so the
repo and the database agree before anything else changes. Commit that on its
own, before touching the award logic below.

## Step 2 — the corrected design

**The award is not a single `v_points := ...` line to multiply.** That was
this file's original assumption, made before anyone had read the live
function bodies, and it is wrong for `pvp_report_result` / `pvp_settle` —
`record_challenge_run` is the one place it happens to still hold. The real
PvP model, confirmed live on 2026-08-21 (see
`.superpowers/sdd/2026-08-20-avatar-math-skills/live-db-facts.md`,
"Consequence for Ruling R5" — this section is a faithful copy of that
finding, derived from the live function bodies):

- `pvp_payout(result text)` → 300 won / 100 draw / -50 lost (IMMUTABLE).
- `pvp_credit(student, delta)` → the single choke point for every PvP points
  movement; clamps a penalty to the child's balance and returns what it
  applied.
- `pvp_report_result` credits `pvp_payout('won')` early when this player
  completed and the opponent has not reported.
- `pvp_settle(match, force)` computes each player's TARGET payout and credits
  `target - awarded_x`, i.e. it converges rather than adding. Multiplying a
  *delta* here would fight itself across repeated settles.

**Therefore the multiplier must be applied to the TARGET payout, not to a
delta, and the "was it pressed" flag must live on the match row** — a boolean
argument cannot reach `pvp_settle`, which is also called from
`pvp_sweep_stale` and from the opponent's own report.

Corrected patch shape for whoever applies this:

```sql
alter table public.pvp_matches
  add column if not exists perk_used_a boolean not null default false,
  add column if not exists perk_used_b boolean not null default false;

-- Target payout for one player, with their avatar's multiplier applied only to
-- a positive award. A loss pays -50; multiplying a penalty would turn a bought
-- perk into a punishment.
create or replace function public.pvp_target_payout(
  p_student   uuid,
  p_result    text,
  p_perk_used boolean
) returns integer
language sql stable security definer set search_path to 'public'
as $$
  select case
           when p_perk_used and pvp_payout(p_result) > 0
           then floor(pvp_payout(p_result) * avatar_payout_multiplier(p_student))::integer
           else pvp_payout(p_result)
         end;
$$;
```

Then, in re-created copies of the CURRENT live bodies pulled in Step 1 (do
not use this repo's committed source for `pvp_report_result` — it is stale,
per the gap this file documents above):

- `pvp_report_result`: add a trailing `p_perk_used boolean default false`; set
  `perk_used_a`/`perk_used_b` in the same `update` that sets `completed_a`/`_b`,
  using `coalesce(perk_used_x, ...)`-style first-report-wins semantics to match
  the rest of that function; and replace the early
  `pvp_credit(v_me, pvp_payout('won'))` with
  `pvp_credit(v_me, pvp_target_payout(v_me, 'won', <this player's flag>))`.
- `pvp_settle`: replace each `pvp_payout(...)` in the two `pvp_credit` calls
  with `pvp_target_payout(v_m.player_a, ..., v_m.perk_used_a)` and the
  `player_b` equivalent.
- `record_challenge_run`: this one IS a single line — add a trailing
  `p_perk_used boolean default false` and apply the multiplier to
  `v_points := 50 + p_solved * 5 + p_best_streak * 3;` under the same
  `p_perk_used and v_points > 0` guard.

### Why the `> 0` guard

A PvP loss awards **negative** points, and multiplying a penalty would turn a
bought perk into a punishment — the guard keeps the multiplier a pure upside.
It lives inside `pvp_target_payout` for the two PvP paths, and inline for
`record_challenge_run`.

## Grants for the new signatures

Re-issue grants for every new signature — `pvp_target_payout` included — and
drop an old signature only after the new one exists:

```sql
revoke all on function public.pvp_target_payout(uuid, text, boolean) from public;
grant  execute on function public.pvp_target_payout(uuid, text, boolean) to authenticated;

revoke execute on function public.pvp_report_result(uuid, integer, boolean, boolean) from public, anon;
grant  execute on function public.pvp_report_result(uuid, integer, boolean, boolean) to authenticated;

revoke execute on function public.record_challenge_run(text, integer, integer, integer, integer, integer, boolean, boolean) from public, anon;
grant  execute on function public.record_challenge_run(text, integer, integer, integer, integer, integer, boolean, boolean) to authenticated;
```

## Dropping the old signatures

Do **not** drop the old 3-argument `pvp_report_result` or the old
7-argument `record_challenge_run` in the same migration that adds the new
ones. The defaulted trailing `p_perk_used` argument is what lets existing
callers (an app build that hasn't shipped the perk UI yet) keep calling the
old signature's shape unchanged after this migration lands — the client and
the migration do not need to roll out in lockstep. Drop the old signature only
in a later migration, once the new one is confirmed live and callers have
moved off it, and only if leaving both in place would otherwise make a call
site ambiguous.
