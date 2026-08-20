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

## Step 2 — the clause each function gains

### `pvp_report_result`

New signature:
`public.pvp_report_result(p_match_id uuid, p_score integer, p_completed boolean default false, p_perk_used boolean default false)`

Take the baseline body pulled in Step 1 and change **only** the award,
immediately before it is written to `students` — nothing else in the deployed
function should move:

```sql
v_points := case
              when p_perk_used and v_points > 0
              then floor(v_points * avatar_payout_multiplier(v_student_id))
              else v_points
            end;
```

### `record_challenge_run`

New signature:
`public.record_challenge_run(p_chapter_id text, p_solved integer, p_total integer, p_best_streak integer, p_attempted integer, p_correct integer, p_passed boolean, p_perk_used boolean default false)`

Apply the same clause immediately after the existing award line:

```sql
v_points := 50 + p_solved * 5 + p_best_streak * 3;
v_points := case
              when p_perk_used and v_points > 0
              then floor(v_points * avatar_payout_multiplier(v_student_id))
              else v_points
            end;
```

### Why the `v_points > 0` guard

A PvP loss awards **negative** points, and multiplying a penalty would turn a
bought perk into a punishment — the guard keeps the multiplier a pure upside.

## Grants for the new signatures

```sql
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
