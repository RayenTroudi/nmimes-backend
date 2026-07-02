create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_parents_updated_at on parents;
create trigger trg_parents_updated_at
  before update on parents
  for each row execute function set_updated_at();

drop trigger if exists trg_students_updated_at on students;
create trigger trg_students_updated_at
  before update on students
  for each row execute function set_updated_at();

drop trigger if exists trg_homework_sessions_updated_at on homework_sessions;
create trigger trg_homework_sessions_updated_at
  before update on homework_sessions
  for each row execute function set_updated_at();
