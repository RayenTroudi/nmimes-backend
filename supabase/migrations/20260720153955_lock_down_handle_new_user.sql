-- supabase/migrations/20260720153955_lock_down_handle_new_user.sql
--
-- Backfilled from the live database. Hardens the signup trigger function:
-- pins its search_path and removes any broad EXECUTE grant, so it can only ever
-- run as the AFTER INSERT trigger on auth.users (owner/service_role), never be
-- invoked directly by a client. The definition itself is set in
-- 20260720153557_auth_rpcs_and_signup_trigger_fix; this only locks privileges.

alter function public.handle_new_user() set search_path to 'public';

revoke execute on function public.handle_new_user() from public, anon, authenticated;
