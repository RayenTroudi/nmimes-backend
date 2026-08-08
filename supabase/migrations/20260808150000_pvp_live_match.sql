-- supabase/migrations/20260808150000_pvp_live_match.sql
--
-- Live head-to-head play: the two paired players exchange progress over a
-- Realtime broadcast channel, so each one's race bar shows the other's real
-- answers arriving.
--
-- Why broadcast and not a table:
--   The race needs the opponent's answer within a few hundred milliseconds.
--   Routing every answer through an insert would add a write per answer plus
--   WAL replication latency, to carry a number that is worthless ten seconds
--   later. Nothing here needs to survive a restart — the authoritative result
--   is still written once, at the end, by pvp_report_result.
--
-- Why the channel is PRIVATE:
--   A public channel named after the match id would be secured only by that id
--   being hard to guess. Anyone who learned one could silently watch a child's
--   match. Private channels put the check in the database instead: Realtime
--   consults RLS on realtime.messages for every subscribe and every publish.
--
--   That table has RLS enabled and, until this migration, no policies at all —
--   so it denied everything and no private channel could work.

-- Is the caller allowed on this match's channel?
--
-- Kept as a function rather than inlined into the policy for two reasons: the
-- uuid cast must not be able to raise (a malformed topic is a "no", not an
-- error, and policies cannot rely on AND short-circuiting to protect a cast),
-- and pvp_matches is read here under RLS the caller does not have.
create or replace function public.pvp_can_use_match_topic(p_topic text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  -- 'pvp:match:' is ten characters; the rest must be the match id.
  if p_topic is null or p_topic not like 'pvp:match:%' then
    return false;
  end if;

  begin
    v_id := substring(p_topic from 11)::uuid;
  exception when others then
    return false;
  end;

  return exists (
    select 1
      from pvp_matches m
     where m.id = v_id
       and (m.player_a = auth.uid() or m.player_b = auth.uid())
       -- A match nobody is still playing should not leave a live channel open
       -- indefinitely. Well past the length of a match, well short of forever.
       and m.created_at > now() - interval '1 hour'
  );
end;
$$;

revoke execute on function public.pvp_can_use_match_topic(text) from public, anon;
grant  execute on function public.pvp_can_use_match_topic(text) to authenticated;

-- Receiving: subscribe to a match channel you are a participant in.
drop policy if exists pvp_match_channel_read on realtime.messages;
create policy pvp_match_channel_read on realtime.messages
  for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and public.pvp_can_use_match_topic(realtime.topic())
  );

-- Publishing: same test. Without this a participant could listen but never
-- send, and every race bar would stay empty.
drop policy if exists pvp_match_channel_write on realtime.messages;
create policy pvp_match_channel_write on realtime.messages
  for insert
  to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and public.pvp_can_use_match_topic(realtime.topic())
  );
