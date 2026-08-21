-- supabase/migrations/20260821171000_claim_badge_reward.sql
--
-- Claiming a badge. Idempotent by construction: the primary key on
-- (student_id, badge_code) is the lock, so two taps that arrive together
-- cannot both insert and cannot both pay.

-- NM- plus six characters a child can read aloud at a till: no O/0, no I/1.
create or replace function public.mint_coupon_code()
returns text
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
  v_try  integer := 0;
begin
  loop
    v_code := 'NM-';
    for i in 1..6 loop
      -- 256 is a whole multiple of the 32-character alphabet, so the
      -- modulo is uniform rather than biased towards the early letters.
      v_code := v_code || substr(
        v_alphabet,
        1 + (get_byte(gen_random_bytes(1), 0) % length(v_alphabet)),
        1);
    end loop;
    exit when not exists (
      select 1 from student_badge_claims where coupon_code = v_code);
    v_try := v_try + 1;
    -- Will not happen at 32^6. Must not spin forever if it does.
    if v_try > 20 then raise exception 'coupon_code_exhausted'; end if;
  end loop;
  return v_code;
end;
$function$;

create or replace function public.claim_badge_reward(p_badge_code text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_student  uuid := auth.uid();
  v_badge    badges%rowtype;
  v_claim    student_badge_claims%rowtype;
  v_existing boolean := false;
  v_code     text;
  v_points   integer := 0;
  v_expires  timestamptz;
begin
  if v_student is null
     or not exists (select 1 from students where id = v_student) then
    raise exception 'not_authenticated';
  end if;

  select * into v_badge from badges
   where code = p_badge_code and is_active;
  if not found then raise exception 'badge_unknown'; end if;

  -- Already claimed: say so and pay nothing. This is the common path for a
  -- child reopening a coupon, not an error.
  select * into v_claim from student_badge_claims
   where student_id = v_student and badge_code = p_badge_code;
  if found then
    return jsonb_build_object(
      'already_claimed',   true,
      'points_awarded',    v_claim.points_awarded,
      'coupon_code',       v_claim.coupon_code,
      'coupon_expires_at', v_claim.coupon_expires_at,
      'new_balance',
        (select points_balance from students where id = v_student));
  end if;

  -- Re-derived here, never taken from the client. The screen's opinion that
  -- a badge is unlocked is a rendering decision, not an authorisation.
  if not badge_unlocked(v_student, p_badge_code) then
    raise exception 'badge_locked';
  end if;

  if v_badge.reward_kind = 'points' then
    v_points := v_badge.reward_points;
  else
    v_code    := mint_coupon_code();
    v_expires := now() + make_interval(days => v_badge.coupon_validity_days);
  end if;

  insert into student_badge_claims
    (student_id, badge_code, points_awarded, coupon_code, coupon_expires_at)
  values
    (v_student, p_badge_code, v_points, v_code, v_expires)
  on conflict (student_id, badge_code) do nothing
  returning * into v_claim;

  if v_claim.student_id is null then
    -- A concurrent call won the insert. Return its claim; pay nothing.
    select * into v_claim from student_badge_claims
     where student_id = v_student and badge_code = p_badge_code;
    v_existing := true;
  elsif v_points > 0 then
    perform set_config('app.allow_points_write', '1', true);
    update students
       set points_balance = points_balance + v_points,
           updated_at     = now()
     where id = v_student;
    perform set_config('app.allow_points_write', '0', true);
  end if;

  return jsonb_build_object(
    'already_claimed',   v_existing,
    'points_awarded',    v_claim.points_awarded,
    'coupon_code',       v_claim.coupon_code,
    'coupon_expires_at', v_claim.coupon_expires_at,
    'new_balance',
      (select points_balance from students where id = v_student));
end;
$function$;

revoke all on function public.mint_coupon_code() from public, anon, authenticated;
revoke all on function public.claim_badge_reward(text) from public, anon;
grant execute on function public.claim_badge_reward(text) to authenticated;
