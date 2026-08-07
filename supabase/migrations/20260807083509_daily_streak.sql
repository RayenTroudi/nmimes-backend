-- supabase/migrations/20260807083509_daily_streak.sql
--
-- Daily login streak, chess.com style: how many consecutive days the child has
-- opened the app. The server decides what "today" is (Africa/Tunis, so the
-- streak rolls over at the midnight the child actually experiences), which also
-- means the streak cannot be extended by changing the device clock.

alter table students add column if not exists current_streak integer not null default 0;
alter table students add column if not exists longest_streak integer not null default 0;
alter table students add column if not exists last_active_on date;

-- Extend the anti-tamper guard: a student may not edit their own streak columns
-- directly, only through touch_streak(), which opens a transaction-local gate.
-- Mirrors how points_balance is protected (see 20260806135223_points_award_gate),
-- with a separate gate so the two stay independent and explicit.
create or replace function public.protect_student_self_update()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() = new.id then
    new.parent_id := old.parent_id;
    new.username  := old.username;
    if coalesce(current_setting('app.allow_points_write', true), '') <> '1' then
      new.points_balance := old.points_balance;
    end if;
    if coalesce(current_setting('app.allow_streak_write', true), '') <> '1' then
      new.current_streak := old.current_streak;
      new.longest_streak := old.longest_streak;
      new.last_active_on := old.last_active_on;
    end if;
  end if;
  return new;
end;
$$;

-- Record that the signed-in student opened the app today, and return the streak.
-- Idempotent within a day, so the client may call it on every load.
--
--   last_active_on = today     -> unchanged
--   last_active_on = yesterday -> current_streak + 1
--   older, or null             -> current_streak = 1
--
-- longest_streak keeps the high-water mark across resets. The returned value is
-- authoritative: the stored current_streak is only refreshed on a touch, so a
-- lapsed streak still reads as its old value until the child comes back — always
-- display what this function returns rather than the raw column.
create or replace function touch_streak()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid := auth.uid();
  v_today   date;
  v_last    date;
  v_current integer;
  v_longest integer;
begin
  if v_student_id is null
     or not exists (select 1 from students where id = v_student_id) then
    raise exception 'not_authenticated';
  end if;

  v_today := (now() at time zone 'Africa/Tunis')::date;

  select last_active_on, coalesce(current_streak, 0), coalesce(longest_streak, 0)
    into v_last, v_current, v_longest
    from students
   where id = v_student_id;

  if v_last = v_today then
    null;                                   -- already counted today
  elsif v_last = v_today - 1 then
    v_current := v_current + 1;             -- consecutive day
  else
    v_current := 1;                         -- first ever, or streak broken
  end if;

  v_longest := greatest(v_longest, v_current);

  if v_last is distinct from v_today then
    perform set_config('app.allow_streak_write', '1', true);
    update students
       set current_streak = v_current,
           longest_streak = v_longest,
           last_active_on = v_today,
           updated_at     = now()
     where id = v_student_id;
    perform set_config('app.allow_streak_write', '0', true);
  end if;

  return jsonb_build_object(
    'current_streak', v_current,
    'longest_streak', v_longest,
    'last_active_on', v_today
  );
end;
$$;

revoke execute on function touch_streak() from public;
revoke execute on function touch_streak() from anon;
grant  execute on function touch_streak() to authenticated;
