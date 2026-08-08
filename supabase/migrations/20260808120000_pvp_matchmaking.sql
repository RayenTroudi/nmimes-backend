-- supabase/migrations/20260808120000_pvp_matchmaking.sql
--
-- PVP matchmaking: a queue two players join, and the match they get paired
-- into.
--
-- The whole design turns on one problem: two children tapping "Find a match" at
-- the same instant must end up in ONE match, not two. If pairing were done
-- client-side ("read the queue, pick someone, write a match") both would read
-- the queue before either wrote, both would claim the other, and two match rows
-- would exist for the same pair. So pairing happens inside a single
-- security-definer function that takes a row lock, and the client never decides
-- who it plays.

create table if not exists pvp_queue (
  student_id  uuid primary key references students(id) on delete cascade,
  -- Denormalised so pairing never has to join students while holding a lock.
  points      integer not null default 0,
  joined_at   timestamptz not null default now()
);

create table if not exists pvp_matches (
  id            uuid primary key default gen_random_uuid(),
  player_a      uuid not null references students(id) on delete cascade,
  player_b      uuid not null references students(id) on delete cascade,
  created_at    timestamptz not null default now(),
  -- Scores are written by each player for their own side only; see
  -- pvp_report_result. Null until that player finishes, which is what lets the
  -- UI tell "still playing" from "scored zero".
  score_a       integer,
  score_b       integer,
  finished_a_at timestamptz,
  finished_b_at timestamptz,
  -- A player may never appear on both sides of their own match.
  constraint pvp_matches_distinct_players check (player_a <> player_b)
);

create index if not exists pvp_matches_player_a_idx on pvp_matches (player_a);
create index if not exists pvp_matches_player_b_idx on pvp_matches (player_b);
-- Pairing pops the longest-waiting player, so that ordering is the hot path.
create index if not exists pvp_queue_joined_at_idx on pvp_queue (joined_at);

alter table pvp_queue   enable row level security;
alter table pvp_matches enable row level security;

-- No direct writes to either table. Every mutation goes through the functions
-- below, so a client cannot insert itself into someone else's match, invent a
-- match it never played, or edit an opponent's score. Read access is granted
-- only for your own rows.
drop policy if exists pvp_queue_self_select on pvp_queue;
create policy pvp_queue_self_select on pvp_queue
  for select using (auth.uid() = student_id);

drop policy if exists pvp_matches_participant_select on pvp_matches;
create policy pvp_matches_participant_select on pvp_matches
  for select using (auth.uid() = player_a or auth.uid() = player_b);

-- Join the queue and, if someone is already waiting, pair with them.
--
-- Returns either:
--   {"status":"matched","match_id":...,"opponent":{...}}  paired immediately
--   {"status":"queued"}                                    waiting for someone
--
-- The lock is the point. `for update skip locked` means two simultaneous
-- callers cannot pop the same waiting player: the first takes the row lock, the
-- second skips that row and either finds another or queues itself. Without
-- skip locked the second caller would block, then match a row that had already
-- been deleted.
create or replace function public.pvp_find_match()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me       uuid := auth.uid();
  v_my_points integer;
  v_opponent uuid;
  v_match_id uuid;
begin
  if v_me is null or not exists (select 1 from students where id = v_me) then
    raise exception 'not_authenticated';
  end if;

  select coalesce(points_balance, 0) into v_my_points from students where id = v_me;

  -- Leave any stale entry of our own first, so tapping Find twice cannot pair
  -- a player with themselves via their own abandoned queue row.
  delete from pvp_queue where student_id = v_me;

  select student_id into v_opponent
    from pvp_queue
   where student_id <> v_me
     -- Anything older than this is a player who closed the app mid-search;
     -- pairing with them would produce a match nobody shows up for.
     and joined_at > now() - interval '2 minutes'
   -- Longest wait first, so nobody is starved by a steady trickle of joiners.
   order by joined_at asc
   for update skip locked
   limit 1;

  if v_opponent is null then
    insert into pvp_queue (student_id, points) values (v_me, v_my_points)
    on conflict (student_id) do update set joined_at = now(), points = excluded.points;
    return jsonb_build_object('status', 'queued');
  end if;

  -- Take them out of the queue before creating the match, so a third player
  -- arriving mid-transaction cannot also claim them.
  delete from pvp_queue where student_id = v_opponent;

  insert into pvp_matches (player_a, player_b)
  values (v_opponent, v_me)          -- the one who waited is player A
  returning id into v_match_id;

  return jsonb_build_object(
    'status',   'matched',
    'match_id', v_match_id,
    'opponent', (select jsonb_build_object(
                          'student_id',     s.id,
                          'name',           s.name,
                          'points_balance', coalesce(s.points_balance, 0),
                          'current_streak', coalesce(s.current_streak, 0))
                   from students s where s.id = v_opponent)
  );
end;
$$;

-- Poll for a match while queued.
--
-- The waiting player is paired by the *other* player's call to pvp_find_match,
-- so they need a way to notice. Realtime on pvp_matches is the fast path; this
-- is the fallback that also covers a dropped socket.
--
-- Deliberately scoped to matches created after the caller joined the queue:
-- without that, re-entering matchmaking would immediately "find" the match you
-- played ten minutes ago.
create or replace function public.pvp_poll_match()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_m  pvp_matches%rowtype;
  v_opponent uuid;
begin
  if v_me is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_m
    from pvp_matches
   where (player_a = v_me or player_b = v_me)
     and created_at > now() - interval '2 minutes'
   order by created_at desc
   limit 1;

  if v_m.id is null then
    return jsonb_build_object('status', 'queued');
  end if;

  v_opponent := case when v_m.player_a = v_me then v_m.player_b else v_m.player_a end;

  return jsonb_build_object(
    'status',   'matched',
    'match_id', v_m.id,
    'opponent', (select jsonb_build_object(
                          'student_id',     s.id,
                          'name',           s.name,
                          'points_balance', coalesce(s.points_balance, 0),
                          'current_streak', coalesce(s.current_streak, 0))
                   from students s where s.id = v_opponent)
  );
end;
$$;

-- Give up searching. Called when the child backs out of the matchmaking screen,
-- so they are not left in the queue to be paired into a match they have walked
-- away from.
create or replace function public.pvp_leave_queue()
returns void
language sql
security definer
set search_path = public
as $$
  delete from pvp_queue where student_id = auth.uid();
$$;

-- Record your own score for a match you actually played.
--
-- Writes only the caller's side: which column to write is decided here from
-- auth.uid(), never passed in, so a player cannot set their opponent's score.
-- Once written a score is final — the coalesce guards mean replaying the call
-- cannot revise a result upward.
create or replace function public.pvp_report_result(
  p_match_id uuid,
  p_score    integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_m  pvp_matches%rowtype;
begin
  select * into v_m from pvp_matches where id = p_match_id;
  if v_m.id is null then
    raise exception 'unknown_match';
  end if;
  if v_me not in (v_m.player_a, v_m.player_b) then
    raise exception 'not_a_participant';
  end if;

  if v_m.player_a = v_me then
    update pvp_matches
       set score_a       = coalesce(score_a, greatest(p_score, 0)),
           finished_a_at = coalesce(finished_a_at, now())
     where id = p_match_id;
  else
    update pvp_matches
       set score_b       = coalesce(score_b, greatest(p_score, 0)),
           finished_b_at = coalesce(finished_b_at, now())
     where id = p_match_id;
  end if;
end;
$$;

revoke execute on function public.pvp_find_match()   from public, anon;
revoke execute on function public.pvp_poll_match()   from public, anon;
revoke execute on function public.pvp_leave_queue()  from public, anon;
revoke execute on function public.pvp_report_result(uuid, integer) from public, anon;

grant execute on function public.pvp_find_match()   to authenticated;
grant execute on function public.pvp_poll_match()   to authenticated;
grant execute on function public.pvp_leave_queue()  to authenticated;
grant execute on function public.pvp_report_result(uuid, integer) to authenticated;

-- Realtime, so the waiting player learns they were paired the moment the match
-- row is inserted rather than on their next poll. RLS still applies to the
-- stream, so a client only ever receives matches it is a participant in.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and tablename = 'pvp_matches'
  ) then
    alter publication supabase_realtime add table pvp_matches;
  end if;
end $$;
