-- supabase/migrations/20260720153557_auth_rpcs_and_signup_trigger_fix.sql
--
-- Backfilled from the live database (this migration was applied before the repo
-- started tracking timestamped migrations; reconstructed from the current object
-- definitions so `supabase db reset` reproduces the schema). Creates the signup
-- trigger that mirrors an auth.users row into public.parents, plus the parent
-- upsert and student access-code RPCs the app calls directly.

-- New auth user -> parent profile row.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  insert into public.parents (id, email, first_name, last_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Idempotent parent upsert, keyed to the caller's auth.uid().
create or replace function public.upsert_parent(p_first_name text, p_last_name text)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_row public.parents;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  insert into public.parents (id, email, first_name, last_name)
  values (auth.uid(), coalesce(auth.email(), ''), coalesce(p_first_name, ''), coalesce(p_last_name, ''))
  on conflict (id) do update
    set first_name = excluded.first_name,
        last_name  = excluded.last_name,
        email      = excluded.email,
        updated_at = now()
  returning * into v_row;
  return json_build_object(
    'id', v_row.id,
    'first_name', v_row.first_name,
    'last_name', v_row.last_name,
    'email', v_row.email,
    'subscription_status', v_row.subscription_status,
    'created_at', v_row.created_at,
    'updated_at', v_row.updated_at
  );
end;
$$;

-- Verify a 6-digit access code against the caller's own children (bcrypt).
create or replace function public.verify_access_code(p_access_code text)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_student public.students;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if p_access_code !~ '^[0-9]{6}$' then
    raise exception 'invalid_access_code_format';
  end if;

  select * into v_student
  from public.students s
  where s.parent_id = auth.uid()
    and s.access_code_hash = extensions.crypt(p_access_code, s.access_code_hash)
  limit 1;

  if v_student.id is null then
    raise exception 'access_code_not_found';
  end if;

  return json_build_object(
    'id', v_student.id, 'parent_id', v_student.parent_id, 'name', v_student.name,
    'username', v_student.username, 'grade', v_student.grade,
    'interest', v_student.interest, 'points_balance', v_student.points_balance,
    'avatar_url', v_student.avatar_url, 'created_at', v_student.created_at,
    'updated_at', v_student.updated_at
  );
end;
$$;

revoke execute on function public.upsert_parent(text, text) from public, anon;
grant  execute on function public.upsert_parent(text, text) to authenticated;

revoke execute on function public.verify_access_code(text) from public, anon;
grant  execute on function public.verify_access_code(text) to authenticated;
