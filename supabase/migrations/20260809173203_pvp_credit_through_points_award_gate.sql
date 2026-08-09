-- pvp_credit's balance write was being silently reverted.
--
-- students carries trg_protect_student_self_update, which throws away any
-- change to points_balance when auth.uid() = students.id unless
-- app.allow_points_write is set — the gate that stops a child editing their own
-- points (see 20260806135223_points_award_gate).
--
-- Every PVP report happens under exactly that condition: the player reporting
-- the result is the player being paid for it. So the match ledger recorded the
-- award and the balance did not move. It looked correct under test only because
-- a SQL session has no auth.uid() to trip the trigger — the bug was invisible
-- to every check that did not authenticate as the student.
--
-- record_challenge_run already had this right; this makes the PVP path match:
-- open the gate, write, close it immediately, so it is never left open for the
-- rest of the transaction.
create or replace function public.pvp_credit(p_student uuid, p_delta integer)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_balance integer;
  v_applied integer;
begin
  if p_delta = 0 then
    return 0;
  end if;

  select points_balance into v_balance from students where id = p_student for update;
  if v_balance is null then
    return 0;
  end if;

  -- A penalty never takes more than the child has: a negative points balance is
  -- not something this app should be able to show. Clamping here rather than at
  -- the display keeps the ledger honest — awarded_a/awarded_b then record what
  -- was really applied, so a later settlement does not chase the shortfall.
  v_applied := greatest(p_delta, -v_balance);
  if v_applied = 0 then
    return 0;
  end if;

  perform set_config('app.allow_points_write', '1', true);
  update students
     set points_balance = points_balance + v_applied,
         updated_at     = now()
   where id = p_student;
  perform set_config('app.allow_points_write', '0', true);

  return v_applied;
end;
$$;

revoke all on function public.pvp_credit(uuid, integer)
  from public, anon, authenticated, service_role;
