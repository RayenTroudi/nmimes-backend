-- supabase/migrations/20260821090000_avatar_payout_multiplier_grant.sql
--
-- `avatar_payout_multiplier` reads a student's equipped avatar and is meant
-- to be called only from the security-definer award paths that already read
-- everything else about that student (pvp_report_result, pvp_settle,
-- record_challenge_run). 20260820180000_avatar_perks.sql granted it to
-- `authenticated` when it was created, which is wider than it needs: any
-- signed-in client can already call it directly, for no reason the design
-- calls for. Revoking here rather than editing that migration, since it has
-- already shipped.

revoke execute on function public.avatar_payout_multiplier(uuid) from authenticated;
