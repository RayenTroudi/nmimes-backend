-- Close the grants 20260809171012_pvp_points_payout left open.
--
-- `revoke all ... from public` does not remove the per-role EXECUTE that
-- Supabase's ALTER DEFAULT PRIVILEGES hands to anon/authenticated/service_role
-- on every new function in the public schema. So the helpers came out callable
-- by anon — and pvp_settle and pvp_sweep_stale are SECURITY DEFINER functions
-- that take a match or student id, meaning anyone holding the publishable key
-- could have settled any match and credited any balance.
--
-- Every other function in this schema is granted to exactly
-- {authenticated, service_role}. These now match.

-- The reporting entry point: same ACL as pvp_find_match and record_challenge_run.
revoke all on function public.pvp_report_result(uuid, integer, boolean)
  from public, anon;
grant execute on function public.pvp_report_result(uuid, integer, boolean)
  to authenticated, service_role;

-- The helpers are internals, reachable only through the SECURITY DEFINER
-- function above, which runs as its owner. Nothing outside needs to call them.
revoke all on function public.pvp_payout(text)
  from public, anon, authenticated, service_role;
revoke all on function public.pvp_winner(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.pvp_settle(uuid, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.pvp_sweep_stale(uuid, interval)
  from public, anon, authenticated, service_role;
