-- supabase/migrations/20260821170000_rewards_badges.sql
--
-- The rewards screen has been showing six hardcoded badges, a hardcoded
-- points figure, and one shared coupon code since it was built. These are
-- the two tables that make it real.
--
-- Deliberately absent: a student_badges table. Whether a badge is unlocked
-- is derived from the student's own runs and matches every time the screen
-- opens (see 20260821170500_rewards_overview.sql), so there is nothing to
-- backfill for the students already here and no threshold change needs a
-- migration to take effect retroactively.

create table if not exists public.badges (
  code                    text primary key,
  icon                    text    not null,
  sort_order              integer not null default 0,
  is_active               boolean not null default true,
  reward_kind             text    not null,
  reward_points           integer not null default 0,
  coupon_partner          text,
  coupon_discount_percent integer,
  coupon_validity_days    integer,
  constraint badges_reward_kind_check
    check (reward_kind in ('points', 'coupon')),
  -- A half-filled row would mint a claim that grants nothing, and it would
  -- do it silently. Either shape is complete or the insert fails.
  constraint badges_reward_shape_check check (
    (reward_kind = 'points'
       and reward_points > 0
       and coupon_partner is null
       and coupon_discount_percent is null
       and coupon_validity_days is null)
    or
    (reward_kind = 'coupon'
       and reward_points = 0
       and coupon_partner is not null
       and coupon_discount_percent between 1 and 100
       and coupon_validity_days > 0)
  )
);

alter table public.badges enable row level security;

-- A catalogue. Every signed-in child sees the same rows; nothing here is
-- personal, and the app needs it before it knows which badges are unlocked.
drop policy if exists badges_read on public.badges;
create policy badges_read on public.badges
  for select to authenticated using (true);

create table if not exists public.student_badge_claims (
  student_id        uuid        not null references public.students(id) on delete cascade,
  badge_code        text        not null references public.badges(code),
  claimed_at        timestamptz not null default now(),
  -- What was actually paid, not what the badge is worth today. Retuning a
  -- reward later must not rewrite what a child was told they earned.
  points_awarded    integer     not null default 0,
  coupon_code       text,
  coupon_expires_at timestamptz,
  primary key (student_id, badge_code)
);

-- The uniqueness that makes claiming idempotent under a double tap.
create unique index if not exists student_badge_claims_coupon_code_idx
  on public.student_badge_claims (coupon_code)
  where coupon_code is not null;

alter table public.student_badge_claims enable row level security;

-- Readable by the child it belongs to. Writes come only from
-- claim_badge_reward(), so there is deliberately no insert policy.
drop policy if exists student_badge_claims_read_own on public.student_badge_claims;
create policy student_badge_claims_read_own on public.student_badge_claims
  for select to authenticated using (student_id = auth.uid());

-- Seeds. Points scale with difficulty; the two hardest badges grant the
-- partner coupon, so the ticket is something a child works towards rather
-- than something everyone holds by their second session.
insert into public.badges
  (code, icon, sort_order, reward_kind, reward_points,
   coupon_partner, coupon_discount_percent, coupon_validity_days)
values
  ('quick_thinker', '⚡',  1, 'points',  50, null, null, null),
  ('first_win',     '🏆',  2, 'points',  75, null, null, null),
  ('team_player',   '🤝',  3, 'points',  50, null, null, null),
  ('perfect_score', '💯',  4, 'points', 100, null, null, null),
  ('math_wizard',   '🧙',  5, 'coupon',   0, 'LearnHub Bookstore', 10, 90),
  ('legend',        '🏅',  6, 'coupon',   0, 'LearnHub Bookstore', 20, 90)
on conflict (code) do nothing;
