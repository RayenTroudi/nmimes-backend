-- Pin pvp_payout's search_path, which the database linter flags
-- (0011_function_search_path_mutable).
--
-- The function resolves no tables and no operators beyond integer comparison,
-- so there is nothing here to hijack today — but every other function in this
-- schema pins it, and a helper that is one edit away from touching a table
-- should not be the exception.
create or replace function public.pvp_payout(p_result text)
returns integer
language sql
immutable
set search_path to 'public'
as $$
  select case p_result
           when 'won'  then 300
           when 'draw' then 100
           else              50
         end;
$$;

-- CREATE OR REPLACE re-applies the schema's default privileges, so the lock
-- down has to be repeated. This helper is internal to pvp_report_result, which
-- runs as its owner and does not need a grant to reach it.
revoke all on function public.pvp_payout(text)
  from public, anon, authenticated, service_role;
