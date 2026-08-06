-- supabase/migrations/20260720170041_insert_student_profile_rpc.sql
--
-- Backfilled from the live database. Creates the student profile alongside a
-- freshly-minted auth user. Called only by the `create-student` edge function
-- (service role), which mints the auth user first and passes its id as p_id;
-- the access code is stored bcrypt-hashed. Not granted to anon/authenticated.

create or replace function public.insert_student_profile(
  p_id         uuid,
  p_parent_id  uuid,
  p_name       text,
  p_username   text,
  p_access_code text,
  p_grade      text default null,
  p_interest   text default null
)
returns json
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_student public.students;
begin
  if p_access_code !~ '^[0-9]{6}$' then
    raise exception 'invalid_access_code_format';
  end if;

  insert into public.students
    (id, parent_id, name, username, grade, interest, access_code_hash)
  values (
    p_id, p_parent_id, trim(p_name), lower(trim(p_username)), p_grade, p_interest,
    extensions.crypt(p_access_code, extensions.gen_salt('bf'))
  )
  returning * into v_student;

  return json_build_object(
    'id', v_student.id, 'parent_id', v_student.parent_id, 'name', v_student.name,
    'username', v_student.username, 'grade', v_student.grade,
    'interest', v_student.interest, 'points_balance', v_student.points_balance,
    'avatar_url', v_student.avatar_url, 'created_at', v_student.created_at,
    'updated_at', v_student.updated_at
  );
end;
$$;

revoke execute on function
  public.insert_student_profile(uuid, uuid, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function
  public.insert_student_profile(uuid, uuid, text, text, text, text, text)
  to service_role;
