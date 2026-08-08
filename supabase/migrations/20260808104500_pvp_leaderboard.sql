-- supabase/migrations/20260808104500_pvp_leaderboard.sql
--
-- The PVP leaderboard: the top students by points, plus where the caller
-- stands.
--
-- This needs a security-definer function rather than a plain select. RLS on
-- students is deliberately self-scoped (students_self_select: auth.uid() = id),
-- so a child selecting from students sees exactly one row — their own. A
-- leaderboard is the one place a child is meant to see other children, and
-- widening the RLS policy to allow it would expose every column of every row
-- to every signed-in user.
--
-- So the exposure is inverted: the policy stays shut, and this function is the
-- single narrow window through it. It returns only what a scoreboard needs —
-- display name, points, streak — and never username, access_code_hash,
-- parent_id, grade or avatar. Those stay unreadable across accounts.
--
-- Display name only: `name` is the child's chosen display name, which is
-- already shown to opponents during a match, whereas `username` is half of
-- their sign-in credential and must never leak.

create or replace function public.pvp_leaderboard(p_limit integer default 20)
returns table (
  student_id     uuid,
  rank           integer,
  name           text,
  points_balance integer,
  current_streak integer,
  is_you         boolean
)
language sql
security definer
set search_path = public
stable
as $$
  with ranked as (
    select
      s.id,
      -- rank(), not row_number(): students tied on points share a place, so
      -- two children on 1650 are both 3rd rather than one being arbitrarily
      -- ordered above the other. Name breaks the tie for display order only,
      -- so the list is stable between loads instead of shuffling.
      rank() over (order by s.points_balance desc)::integer as rank,
      s.name,
      coalesce(s.points_balance, 0) as points_balance,
      coalesce(s.current_streak, 0) as current_streak,
      s.id = auth.uid() as is_you
    from students s
    -- A child who has never scored is not "last", they are simply not on the
    -- board yet. Listing a wall of zeroes would bury the actual competition.
    where coalesce(s.points_balance, 0) > 0
    order by s.points_balance desc, s.name asc
  )
  select id, rank, name, points_balance, current_streak, is_you
  from ranked
  -- Clamped server-side: the limit is a client-supplied number, and an
  -- unbounded one would let any signed-in user pull the entire student table
  -- one page at a time.
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
$$;

-- Where the caller stands, computed over every student rather than only the
-- page returned above — otherwise a child outside the top 20 would have no
-- rank at all, or worse, a flattering one.
--
-- Returns rank null when the student has yet to score, which the client shows
-- as an em dash rather than inventing a position.
create or replace function public.pvp_my_standing()
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'rank',           (select rank
                         from (select id,
                                      rank() over (order by points_balance desc) as rank
                                 from students
                                where coalesce(points_balance, 0) > 0) r
                        where r.id = auth.uid()),
    'points_balance', coalesce((select points_balance from students where id = auth.uid()), 0),
    'current_streak', coalesce((select current_streak from students where id = auth.uid()), 0),
    'total_ranked',   (select count(*) from students where coalesce(points_balance, 0) > 0)
  );
$$;

-- Signed-in students and parents only. Revoked from anon so the board is not a
-- public listing of children's names readable with the publishable key alone.
revoke execute on function public.pvp_leaderboard(integer) from public;
revoke execute on function public.pvp_leaderboard(integer) from anon;
grant  execute on function public.pvp_leaderboard(integer) to authenticated;

revoke execute on function public.pvp_my_standing() from public;
revoke execute on function public.pvp_my_standing() from anon;
grant  execute on function public.pvp_my_standing() to authenticated;

-- The board sorts every ranked student by points on each load.
create index if not exists students_points_balance_idx
  on students (points_balance desc)
  where points_balance > 0;
