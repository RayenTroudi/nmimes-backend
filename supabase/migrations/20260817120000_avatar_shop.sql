-- supabase/migrations/20260817120000_avatar_shop.sql
--
-- Avatar shop: a priced catalogue, per-student ownership, and the equipped
-- avatar. Points are spent through a security-definer RPC because
-- students.points_balance is reverted by trg_protect_student_self_update on
-- any self-update unless the txn-local gate app.allow_points_write = '1'.

create table if not exists public.avatars (
  code       text primary key,
  price      integer not null check (price >= 0),
  sort_order integer not null default 0,
  is_active  boolean not null default true
);

create table if not exists public.student_avatars (
  student_id  uuid    not null references public.students(id) on delete cascade,
  avatar_code text    not null references public.avatars(code),
  price_paid  integer not null,
  acquired_at timestamptz not null default now(),
  primary key (student_id, avatar_code)
);

alter table public.students
  add column if not exists avatar_code text references public.avatars(code);

insert into public.avatars (code, price, sort_order) values
  ('nmimes_celebrate',        0,   1),
  ('nmimes_matcha',           0,   2),
  ('nmimes_surprised1',     150,   3),
  ('nmimes_cry',            150,   4),
  ('nmimes_inlove',         300,   5),
  ('nmimes_like_sideprofile', 300, 6),
  ('nmimes_football1',      300,   7),
  ('nmimes_kiss',           500,   8),
  ('nmimes_surprised2',     500,   9)
on conflict (code) do nothing;

alter table public.avatars        enable row level security;
alter table public.student_avatars enable row level security;

drop policy if exists avatars_read_all on public.avatars;
create policy avatars_read_all on public.avatars
  for select to authenticated using (true);

-- Own rows, or a parent reading their child's.
drop policy if exists student_avatars_read_own on public.student_avatars;
create policy student_avatars_read_own on public.student_avatars
  for select to authenticated
  using (
    student_id = auth.uid()
    or exists (
      select 1 from public.students s
      where s.id = student_avatars.student_id and s.parent_id = auth.uid()
    )
  );
-- No insert/update/delete policy: only the SECURITY DEFINER RPC writes here.

-- students.avatar_code is NOT covered by trg_protect_student_self_update, so
-- without this a child could equip an avatar they never bought by writing the
-- column directly. This is the real ownership boundary; the RPC check alone is
-- not sufficient.
create or replace function public.enforce_avatar_ownership()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.avatar_code is null or new.avatar_code is not distinct from old.avatar_code then
    return new;
  end if;
  if exists (select 1 from avatars a where a.code = new.avatar_code and a.price = 0) then
    return new;  -- free avatars belong to everyone
  end if;
  if not exists (
    select 1 from student_avatars sa
    where sa.student_id = new.id and sa.avatar_code = new.avatar_code
  ) then
    raise exception 'avatar_not_owned';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_avatar_ownership on public.students;
create trigger trg_enforce_avatar_ownership
  before update on public.students
  for each row execute function public.enforce_avatar_ownership();

create or replace function public.purchase_avatar(p_code text)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_student  students%rowtype;
  v_price    integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  -- Serialises double taps: the second call sees the debited balance.
  select * into v_student from students where id = auth.uid() for update;
  if not found then
    raise exception 'not_authenticated';
  end if;

  select price into v_price
  from avatars where code = p_code and is_active;
  if v_price is null then
    raise exception 'avatar_unavailable';
  end if;

  if v_price = 0 or exists (
    select 1 from student_avatars
    where student_id = v_student.id and avatar_code = p_code
  ) then
    raise exception 'already_owned';
  end if;

  if v_student.points_balance < v_price then
    raise exception 'insufficient_points';
  end if;

  insert into student_avatars (student_id, avatar_code, price_paid)
  values (v_student.id, p_code, v_price);

  -- Open the sanctioned gate so the protect trigger lets the debit through.
  perform set_config('app.allow_points_write', '1', true);

  update students
     set points_balance = points_balance - v_price,
         avatar_code    = p_code
   where id = v_student.id
  returning points_balance into v_student.points_balance;

  -- Close the gate as soon as the sanctioned write is done, so it cannot leak
  -- to later statements in the same transaction.
  perform set_config('app.allow_points_write', '0', true);

  return json_build_object(
    'points_balance', v_student.points_balance,
    'avatar_code',    p_code
  );
end;
$$;

create or replace function public.equip_avatar(p_code text)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_balance integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  -- trg_enforce_avatar_ownership rejects an unowned code.
  update students set avatar_code = p_code
   where id = auth.uid()
  returning points_balance into v_balance;

  return json_build_object('points_balance', v_balance, 'avatar_code', p_code);
end;
$$;

revoke all on function public.purchase_avatar(text) from public;
revoke all on function public.equip_avatar(text)   from public;
grant execute on function public.purchase_avatar(text) to authenticated;
grant execute on function public.equip_avatar(text)    to authenticated;
