-- supabase/migrations/20260820180000_avatar_perks.sql
--
-- Avatar skills.
--
-- Each catalogue row may name a perk. Most perks live entirely on the client —
-- a hint, a crossed-out option, a forgiven heart — and the server neither knows
-- nor cares when they fire. Three of them move points, and those are applied
-- here instead, from the student's OWN equipped avatar: the client reports only
-- that the button was pressed, so a patched build cannot award itself a perk it
-- did not buy.
--
-- This migration is purely additive: a new column, catalogue backfill, and a
-- new function. It does not touch pvp_report_result or record_challenge_run —
-- see PENDING_award_perk_multiplier.md for why wiring the multiplier into
-- those two award paths has to wait.

alter table public.avatars add column if not exists perk_code text;

update public.avatars set perk_code = 'geometric_streak' where code = 'nmimes_celebrate';
update public.avatars set perk_code = 'steady_state'     where code = 'nmimes_matcha';
update public.avatars set perk_code = 'estimation'       where code = 'nmimes_surprised1';
update public.avatars set perk_code = 'the_remainder'    where code = 'nmimes_cry';
update public.avatars set perk_code = 'bisection'        where code = 'nmimes_inlove';
update public.avatars set perk_code = 'percent_gain'     where code = 'nmimes_like_sideprofile';
update public.avatars set perk_code = 'momentum'         where code = 'nmimes_football1';
update public.avatars set perk_code = 'common_factor'    where code = 'nmimes_kiss';
update public.avatars set perk_code = 'prime_check'      where code = 'nmimes_surprised2';

-- The multiplier for a student's equipped avatar, or 1.0 for no avatar, no
-- perk, or a perk that does not touch points.
create or replace function public.avatar_payout_multiplier(p_student uuid)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select case a.perk_code
           when 'percent_gain'     then 1.25
           when 'momentum'         then 1.10
           when 'geometric_streak' then 1.10
           else 1.0
         end
    from students s
    left join avatars a on a.code = s.avatar_code
   where s.id = p_student;
$$;

revoke all on function public.avatar_payout_multiplier(uuid) from public;
grant execute on function public.avatar_payout_multiplier(uuid) to authenticated;
