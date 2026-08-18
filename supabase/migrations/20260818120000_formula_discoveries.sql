-- Saved Formulas becomes a real collection: a formula stated in a snapped
-- lesson or homework is recorded the first time the child finishes that
-- session, and never again.
--
-- The formulas are read off the snap_sessions row rather than passed in by the
-- caller. snap_sessions.formulas is already written by snap-lesson (and, from
-- this release, by snap-homework), so the client has nothing to supply but a
-- session id — which means no caller-chosen formula text can ever reach this
-- table.

-- Identity of a formula, so 'a² + b² = c²' and 'a²+b²=c²' are one discovery.
-- Immutable and server-side on purpose: if the client computed this, the two
-- sides could disagree about what counts as the same formula.
create or replace function public.formula_key(p_expression text)
returns text
language sql
immutable
strict
as $$
  -- Strip every whitespace character, unify the multiplication, division and
  -- minus glyphs a textbook might use, then casefold.
  select lower(
    translate(
      regexp_replace(p_expression, '\s', '', 'g'),
      '×·÷−–',
      '**/--'
    )
  );
$$;

create table if not exists public.formula_discoveries (
  student_id    uuid not null references public.students(id) on delete cascade,
  -- The wording of the FIRST sighting. `on conflict do nothing` leaves this
  -- untouched when the same formula turns up again in a later session.
  expression    text not null,
  formula_key   text not null,
  meaning       jsonb,
  category      text not null default 'other',
  source        text not null,
  -- Losing the session that taught a formula must not un-discover it.
  session_id    uuid references public.snap_sessions(id) on delete set null,
  discovered_at timestamptz not null default now(),
  primary key (student_id, formula_key)
);

create index if not exists formula_discoveries_student_cat_idx
  on public.formula_discoveries (student_id, category, discovered_at desc);

alter table public.formula_discoveries enable row level security;

-- Own rows, or a parent reading their child's — the same shape as
-- student_avatars_read_own.
drop policy if exists formula_discoveries_read_own on public.formula_discoveries;
create policy formula_discoveries_read_own on public.formula_discoveries
  for select to authenticated
  using (
    student_id = auth.uid()
    or exists (
      select 1 from public.students s
      where s.id = formula_discoveries.student_id and s.parent_id = auth.uid()
    )
  );
-- No insert/update/delete policy: the SECURITY DEFINER RPC is the only writer.

create or replace function public.record_formula_discoveries(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_student_id uuid := auth.uid();
  v_session    snap_sessions%rowtype;
  v_inserted   int := 0;
  v_total      int;
begin
  if v_student_id is null then
    raise exception 'not_authenticated';
  end if;

  -- The session must be this child's. Without the check any guessed session id
  -- would do — the same reason record_snap_practice checks ownership.
  select * into v_session
    from snap_sessions
   where id = p_session_id and student_id = v_student_id;
  if not found then
    raise exception 'invalid_session';
  end if;

  with incoming as (
    -- distinct on: two formulas in one session can normalise to the same key,
    -- and ON CONFLICT does not resolve duplicates within a single command.
    select distinct on (formula_key(f->>'expression'))
           f->>'expression'          as expression,
           formula_key(f->>'expression') as key,
           f->'meaning'              as meaning
      from jsonb_array_elements(coalesce(v_session.formulas, '[]'::jsonb)) as f
     where coalesce(btrim(f->>'expression'), '') <> ''
     order by formula_key(f->>'expression')
  ),
  ins as (
    insert into formula_discoveries
      (student_id, expression, formula_key, meaning, category, source, session_id)
    select v_student_id,
           i.expression,
           i.key,
           i.meaning,
           coalesce(v_session.category, 'other'),
           coalesce(v_session.kind, 'lesson'),
           v_session.id
      from incoming i
    on conflict (student_id, formula_key) do nothing
    returning 1
  )
  select count(*) into v_inserted from ins;

  select count(*) into v_total
    from formula_discoveries where student_id = v_student_id;

  return jsonb_build_object('discovered', v_inserted, 'total', v_total);
end;
$$;

revoke all on function public.record_formula_discoveries(uuid) from public;
grant execute on function public.record_formula_discoveries(uuid) to authenticated;
