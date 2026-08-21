-- supabase/migrations/20260821150000_practice_run_payout.sql
--
-- Pay for a PVP-style run that has no opponent to report to.
--
-- Two entry points reach the puzzle screen: matchmaking, which carries a
-- match id and settles through pvp_report_result, and the "Start" button on
-- the PVP dialog, which carries nothing at all. The second kind showed the
-- child a score in the hundreds and credited exactly nothing, because that
-- screen's only award path is the match row it does not have.
--
-- The formula deliberately mirrors record_challenge_run's — solved * 5 plus
-- best_streak * 3 — so a child does not have to hold two ideas about what a
-- run is worth. It drops that function's 50-point bonus, which exists to
-- reward a first clear; a practice run has no chapter to clear and can be
-- replayed forever.
--
-- The on-screen score is NOT the award and is never sent: that number is
-- 30 + streak * 10 per puzzle, about 520 for a clean run, which would mint an
-- avatar every few minutes.

create table if not exists public.practice_runs (
  id             uuid primary key default gen_random_uuid(),
  student_id     uuid not null references public.students(id) on delete cascade,
  solved         integer not null,
  total          integer not null,
  best_streak    integer not null,
  points_awarded integer not null,
  created_at     timestamptz not null default now()
);

-- The daily cap below counts a student's recent paid rows, so that is the
-- shape the index serves.
create index if not exists practice_runs_student_recent_idx
  on public.practice_runs (student_id, created_at desc);

alter table public.practice_runs enable row level security;

-- Readable by the child it belongs to. Writes come only from the definer
-- function below, so there is deliberately no insert policy.
drop policy if exists practice_runs_read_own on public.practice_runs;
create policy practice_runs_read_own on public.practice_runs
  for select to authenticated using (student_id = auth.uid());

-- How many paid practice runs a child may bank in a rolling day.
--
-- A practice run costs nothing to repeat — a perfect run loses no hearts — so
-- without a ceiling this is an unlimited points faucet next to an avatar
-- economy priced at 150-500. Ten paid runs is roughly 550 points a day, in
-- the same order as a good day of chapter work rather than a way around it.
-- Runs past the cap still play and still record; they simply pay nothing.
create or replace function public.practice_run_daily_cap()
returns integer language sql immutable as $$ select 10 $$;

create or replace function public.record_practice_run(
  p_solved      integer,
  p_total       integer,
  p_best_streak integer,
  p_perk_used   boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_student_id uuid := auth.uid();
  v_points     integer := 0;
  v_paid_today integer;
  v_capped     boolean := false;
begin
  if v_student_id is null
     or not exists (select 1 from students where id = v_student_id) then
    raise exception 'not_authenticated';
  end if;

  -- The client reports its own counters, so bound them before they are worth
  -- anything. 20 is well above the eight-puzzle set the app ships and still
  -- far below a number worth farming.
  p_total       := least(greatest(coalesce(p_total, 0), 0), 20);
  p_solved      := least(greatest(coalesce(p_solved, 0), 0), p_total);
  p_best_streak := least(greatest(coalesce(p_best_streak, 0), 0), p_solved);

  v_points := p_solved * 5 + p_best_streak * 3;

  select count(*) into v_paid_today
    from practice_runs
   where student_id = v_student_id
     and points_awarded > 0
     and created_at > now() - interval '24 hours';

  if v_paid_today >= practice_run_daily_cap() then
    v_points := 0;
    v_capped := true;
  end if;

  -- Same rule as everywhere else: a skill only ever scales a positive award.
  if coalesce(p_perk_used, false) and v_points > 0 then
    v_points := floor(
      v_points * coalesce(avatar_payout_multiplier(v_student_id), 1.0)
    )::integer;
  end if;

  insert into practice_runs
    (student_id, solved, total, best_streak, points_awarded)
  values
    (v_student_id, p_solved, p_total, p_best_streak, v_points);

  if v_points > 0 then
    perform set_config('app.allow_points_write', '1', true);
    update students
       set points_balance = points_balance + v_points,
           updated_at     = now()
     where id = v_student_id;
    perform set_config('app.allow_points_write', '0', true);
  end if;

  return jsonb_build_object(
    'points_awarded', v_points,
    'capped',         v_capped,
    'new_balance',    (select points_balance from students where id = v_student_id)
  );
end;
$function$;

revoke all on function public.record_practice_run(integer, integer, integer, boolean) from public, anon;
grant execute on function public.record_practice_run(integer, integer, integer, boolean) to authenticated;
