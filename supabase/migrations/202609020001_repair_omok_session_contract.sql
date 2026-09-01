begin;

-- Some legacy deployments already had omok_sessions before the consolidated
-- baseline ran. Because the baseline uses CREATE TABLE IF NOT EXISTS, these
-- later session columns were never added there. The result-based assignment
-- RPCs require both columns when a game is accepted or rematched.
do $$
begin
  if to_regclass('public.omok_sessions') is null then
    raise exception 'public.omok_sessions is required';
  end if;
end;
$$;

alter table public.omok_sessions
  add column if not exists rematch_of_session_id uuid,
  add column if not exists created_by uuid;

-- Normalize partially deployed columns to the nullable UUID contract. Foreign
-- keys are rebuilt below because PostgreSQL cannot change a referenced column
-- type while an incompatible key remains attached.
do $$
declare
  rematch_attnum smallint;
  rematch_type oid;
  created_by_attnum smallint;
  created_by_type oid;
  existing_constraint record;
begin
  select attnum, atttypid
  into rematch_attnum, rematch_type
  from pg_attribute
  where attrelid = 'public.omok_sessions'::regclass
    and attname = 'rematch_of_session_id'
    and not attisdropped;

  select attnum, atttypid
  into created_by_attnum, created_by_type
  from pg_attribute
  where attrelid = 'public.omok_sessions'::regclass
    and attname = 'created_by'
    and not attisdropped;

  -- These optional relation fields have no default in the canonical schema.
  -- Drop a legacy default before conversion so values such as empty text do
  -- not block the UUID cast and cannot survive after a successful repair.
  alter table public.omok_sessions
    alter column rematch_of_session_id drop default,
    alter column created_by drop default;

  if rematch_type <> 'uuid'::regtype then
    for existing_constraint in
      select constraint_row.conname
      from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.omok_sessions'::regclass
        and constraint_row.contype = 'f'
        and rematch_attnum = any(constraint_row.conkey)
    loop
      execute format(
        'alter table public.omok_sessions drop constraint %I',
        existing_constraint.conname
      );
    end loop;

    alter table public.omok_sessions
      alter column rematch_of_session_id type uuid
      using nullif(btrim(rematch_of_session_id::text), '')::uuid;
  end if;

  if created_by_type <> 'uuid'::regtype then
    for existing_constraint in
      select constraint_row.conname
      from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.omok_sessions'::regclass
        and constraint_row.contype = 'f'
        and created_by_attnum = any(constraint_row.conkey)
    loop
      execute format(
        'alter table public.omok_sessions drop constraint %I',
        existing_constraint.conname
      );
    end loop;

    alter table public.omok_sessions
      alter column created_by type uuid
      using nullif(btrim(created_by::text), '')::uuid;
  end if;

  alter table public.omok_sessions
    alter column rematch_of_session_id drop not null,
    alter column created_by drop not null;
end;
$$;

-- ON DELETE SET NULL means dangling legacy references are semantically null.
-- Clear them before adding the exact foreign-key contract.
update public.omok_sessions target_session
set rematch_of_session_id = null
where target_session.rematch_of_session_id is not null
  and not exists (
    select 1
    from public.omok_sessions source_session
    where source_session.id = target_session.rematch_of_session_id
  );

update public.omok_sessions target_session
set created_by = null
where target_session.created_by is not null
  and not exists (
    select 1
    from auth.users creator
    where creator.id = target_session.created_by
  );

do $$
declare
  rematch_attnum smallint;
  created_by_attnum smallint;
  session_id_attnum smallint;
  auth_user_id_attnum smallint;
  existing_constraint record;
begin
  select attnum into rematch_attnum
  from pg_attribute
  where attrelid = 'public.omok_sessions'::regclass
    and attname = 'rematch_of_session_id'
    and not attisdropped;

  select attnum into created_by_attnum
  from pg_attribute
  where attrelid = 'public.omok_sessions'::regclass
    and attname = 'created_by'
    and not attisdropped;

  select attnum into session_id_attnum
  from pg_attribute
  where attrelid = 'public.omok_sessions'::regclass
    and attname = 'id'
    and not attisdropped;

  select attnum into auth_user_id_attnum
  from pg_attribute
  where attrelid = 'auth.users'::regclass
    and attname = 'id'
    and not attisdropped;

  -- Remove a conflicting canonical name or an incompatible single-column key.
  for existing_constraint in
    select constraint_row.conname
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.omok_sessions'::regclass
      and (
        constraint_row.conname = 'omok_sessions_rematch_of_session_id_fkey'
        or (
          constraint_row.contype = 'f'
          and constraint_row.conkey = array[rematch_attnum]::smallint[]
        )
      )
      and not (
        constraint_row.conkey = array[rematch_attnum]::smallint[]
        and constraint_row.confrelid = 'public.omok_sessions'::regclass
        and constraint_row.confkey = array[session_id_attnum]::smallint[]
        and constraint_row.confdeltype = 'n'
        and constraint_row.convalidated
      )
  loop
    execute format(
      'alter table public.omok_sessions drop constraint %I',
      existing_constraint.conname
    );
  end loop;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.omok_sessions'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.conkey = array[rematch_attnum]::smallint[]
      and constraint_row.confrelid = 'public.omok_sessions'::regclass
      and constraint_row.confkey = array[session_id_attnum]::smallint[]
      and constraint_row.confdeltype = 'n'
      and constraint_row.convalidated
  ) then
    alter table public.omok_sessions
      add constraint omok_sessions_rematch_of_session_id_fkey
      foreign key (rematch_of_session_id)
      references public.omok_sessions(id)
      on delete set null;
  end if;

  for existing_constraint in
    select constraint_row.conname
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.omok_sessions'::regclass
      and (
        constraint_row.conname = 'omok_sessions_created_by_fkey'
        or (
          constraint_row.contype = 'f'
          and constraint_row.conkey = array[created_by_attnum]::smallint[]
        )
      )
      and not (
        constraint_row.conkey = array[created_by_attnum]::smallint[]
        and constraint_row.confrelid = 'auth.users'::regclass
        and constraint_row.confkey = array[auth_user_id_attnum]::smallint[]
        and constraint_row.confdeltype = 'n'
        and constraint_row.convalidated
      )
  loop
    execute format(
      'alter table public.omok_sessions drop constraint %I',
      existing_constraint.conname
    );
  end loop;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.omok_sessions'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.conkey = array[created_by_attnum]::smallint[]
      and constraint_row.confrelid = 'auth.users'::regclass
      and constraint_row.confkey = array[auth_user_id_attnum]::smallint[]
      and constraint_row.confdeltype = 'n'
      and constraint_row.convalidated
  ) then
    alter table public.omok_sessions
      add constraint omok_sessions_created_by_fkey
      foreign key (created_by)
      references auth.users(id)
      on delete set null;
  end if;
end;
$$;

-- Replace same-named but malformed indexes instead of letting IF NOT EXISTS
-- hide drift forever.
do $$
begin
  if to_regclass('public.omok_sessions_couple_created_idx') is not null
     and not exists (
       select 1
       from pg_index index_row
       where index_row.indexrelid =
         to_regclass('public.omok_sessions_couple_created_idx')
         and index_row.indrelid = 'public.omok_sessions'::regclass
         and index_row.indisvalid
         and index_row.indisready
         and not index_row.indisunique
         and index_row.indnkeyatts = 2
         and index_row.indpred is null
         and pg_get_indexdef(index_row.indexrelid, 1, true) = 'couple_id'
         and pg_get_indexdef(index_row.indexrelid, 2, true) = 'created_at'
         and ((index_row.indoption::smallint[])[1] & 1) = 1
     ) then
    drop index public.omok_sessions_couple_created_idx;
  end if;

  if to_regclass('public.omok_sessions_one_rematch_idx') is not null
     and not exists (
       select 1
       from pg_index index_row
       where index_row.indexrelid =
         to_regclass('public.omok_sessions_one_rematch_idx')
         and index_row.indrelid = 'public.omok_sessions'::regclass
         and index_row.indisvalid
         and index_row.indisready
         and index_row.indisunique
         and index_row.indnkeyatts = 1
         and pg_get_indexdef(index_row.indexrelid, 1, true) =
           'rematch_of_session_id'
         and lower(regexp_replace(
           pg_get_expr(index_row.indpred, index_row.indrelid),
           '[[:space:]]+',
           '',
           'g'
         )) = '(rematch_of_session_idisnotnull)'
     ) then
    drop index public.omok_sessions_one_rematch_idx;
  end if;
end;
$$;

create index if not exists omok_sessions_couple_created_idx
  on public.omok_sessions(couple_id, created_at desc);

create unique index if not exists omok_sessions_one_rematch_idx
  on public.omok_sessions(rematch_of_session_id)
  where rematch_of_session_id is not null;

do $$
declare
  rematch_attnum smallint;
  created_by_attnum smallint;
  session_id_attnum smallint;
  auth_user_id_attnum smallint;
  rematch_column_is_valid boolean;
  created_by_column_is_valid boolean;
begin
  select
    attribute_row.attnum,
    attribute_row.atttypid = 'uuid'::regtype
      and not attribute_row.attnotnull
      and not attribute_row.atthasdef
  into rematch_attnum, rematch_column_is_valid
  from pg_attribute attribute_row
  where attribute_row.attrelid = 'public.omok_sessions'::regclass
    and attribute_row.attname = 'rematch_of_session_id'
    and not attribute_row.attisdropped;

  select
    attribute_row.attnum,
    attribute_row.atttypid = 'uuid'::regtype
      and not attribute_row.attnotnull
      and not attribute_row.atthasdef
  into created_by_attnum, created_by_column_is_valid
  from pg_attribute attribute_row
  where attribute_row.attrelid = 'public.omok_sessions'::regclass
    and attribute_row.attname = 'created_by'
    and not attribute_row.attisdropped;

  if not coalesce(rematch_column_is_valid, false)
     or not coalesce(created_by_column_is_valid, false) then
    raise exception 'Omok session columns have an unexpected definition';
  end if;

  select attnum into session_id_attnum
  from pg_attribute
  where attrelid = 'public.omok_sessions'::regclass
    and attname = 'id'
    and not attisdropped;

  select attnum into auth_user_id_attnum
  from pg_attribute
  where attrelid = 'auth.users'::regclass
    and attname = 'id'
    and not attisdropped;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.omok_sessions'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.conkey = array[rematch_attnum]::smallint[]
      and constraint_row.confrelid = 'public.omok_sessions'::regclass
      and constraint_row.confkey = array[session_id_attnum]::smallint[]
      and constraint_row.confdeltype = 'n'
      and constraint_row.convalidated
  ) then
    raise exception 'Omok rematch foreign key has an unexpected definition';
  end if;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.omok_sessions'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.conkey = array[created_by_attnum]::smallint[]
      and constraint_row.confrelid = 'auth.users'::regclass
      and constraint_row.confkey = array[auth_user_id_attnum]::smallint[]
      and constraint_row.confdeltype = 'n'
      and constraint_row.convalidated
  ) then
    raise exception 'Omok creator foreign key has an unexpected definition';
  end if;

  if not exists (
    select 1
    from pg_index index_row
    where index_row.indexrelid =
      'public.omok_sessions_couple_created_idx'::regclass
      and index_row.indrelid = 'public.omok_sessions'::regclass
      and index_row.indisvalid
      and index_row.indisready
      and not index_row.indisunique
      and index_row.indnkeyatts = 2
      and index_row.indpred is null
      and pg_get_indexdef(index_row.indexrelid, 1, true) = 'couple_id'
      and pg_get_indexdef(index_row.indexrelid, 2, true) = 'created_at'
      and ((index_row.indoption::smallint[])[1] & 1) = 1
  ) then
    raise exception 'Omok couple-created index has an unexpected definition';
  end if;

  if not exists (
    select 1
    from pg_index index_row
    where index_row.indexrelid =
      'public.omok_sessions_one_rematch_idx'::regclass
      and index_row.indrelid = 'public.omok_sessions'::regclass
      and index_row.indisvalid
      and index_row.indisready
      and index_row.indisunique
      and index_row.indnkeyatts = 1
      and pg_get_indexdef(index_row.indexrelid, 1, true) =
        'rematch_of_session_id'
      and lower(regexp_replace(
        pg_get_expr(index_row.indpred, index_row.indrelid),
        '[[:space:]]+',
        '',
        'g'
      )) = '(rematch_of_session_idisnotnull)'
  ) then
    raise exception 'Omok rematch index has an unexpected definition';
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
