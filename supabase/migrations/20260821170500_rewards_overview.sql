-- supabase/migrations/20260821170500_rewards_overview.sql
--
-- What the rewards screen reads. Unlocks are computed here rather than
-- stored: the students already in this database have runs and matches
-- worth badges, and event-sourcing would have awarded them nothing
-- without a backfill.

-- A settled match this student outscored the other player in. Unsettled
-- matches do not count, so walking out of a match cannot manufacture a win.
create or replace function public.pvp_win_count(p_student uuid)
returns integer
language sql
stable
security definer
set search_path to 'public'
as $function$
  select count(*)::integer
    from pvp_matches
   where settled_at is not null
     and (   (player_a = p_student and coalesce(score_a, 0) > coalesce(score_b, 0))
          or (player_b = p_student and coalesce(score_b, 0) > coalesce(score_a, 0)));
$function$;

-- The one definition of every badge's rule. Both the display path and the
-- claim path call this, so a badge can never be claimable but not shown, or
-- shown but not claimable.
create or replace function public.badge_unlocked(p_student uuid, p_badge text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select case p_badge
    when 'quick_thinker' then
      exists (select 1 from challenge_runs
               where student_id = p_student and best_streak >= 5)
      or exists (select 1 from practice_runs
                  where student_id = p_student and best_streak >= 5)
    when 'first_win' then
      pvp_win_count(p_student) >= 1
    when 'team_player' then
      exists (select 1 from study_room_members where student_id = p_student)
    when 'math_wizard' then
      (select count(*) from student_chapter_progress
        where student_id = p_student and passed_at is not null) >= 3
    when 'perfect_score' then
      exists (select 1 from challenge_runs
               where student_id = p_student and total > 0 and solved = total)
      or exists (select 1 from practice_runs
                  where student_id = p_student and total > 0 and solved = total)
    when 'legend' then
      pvp_win_count(p_student) >= 10
    -- A badge seeded later with no rule here stays locked rather than
    -- becoming free for everyone.
    else false
  end;
$function$;

create or replace function public.rewards_overview()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_student uuid := auth.uid();
  v_badges  jsonb;
begin
  if v_student is null
     or not exists (select 1 from students where id = v_student) then
    raise exception 'not_authenticated';
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'code',                    b.code,
               'icon',                    b.icon,
               'unlocked',                badge_unlocked(v_student, b.code),
               'claimed',                 c.student_id is not null,
               'reward_kind',             b.reward_kind,
               'reward_points',           b.reward_points,
               'coupon_partner',          b.coupon_partner,
               'coupon_discount_percent', b.coupon_discount_percent,
               -- From the claim, not the badge: the code and expiry only
               -- exist once this child has claimed it, and reopening the
               -- ticket later must not need a second call.
               'coupon_code',             c.coupon_code,
               'coupon_expires_at',       c.coupon_expires_at
             )
             order by b.sort_order
           ),
           '[]'::jsonb)
    into v_badges
    from badges b
    left join student_badge_claims c
      on c.badge_code = b.code
     and c.student_id = v_student
   where b.is_active;

  return jsonb_build_object(
    'points_balance',
      (select points_balance from students where id = v_student),
    'badges', v_badges
  );
end;
$function$;

-- The helpers take a student id, so a signed-in child could otherwise ask
-- about another child. Only the definer RPC above is allowed to call them.
revoke all on function public.pvp_win_count(uuid) from public, anon, authenticated;
revoke all on function public.badge_unlocked(uuid, text) from public, anon, authenticated;

revoke all on function public.rewards_overview() from public, anon;
grant execute on function public.rewards_overview() to authenticated;
