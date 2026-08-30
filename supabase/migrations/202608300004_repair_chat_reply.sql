begin;

-- Some production environments have the chat UI from 202607120004 without
-- its reply column. Keep this repair scoped to messages and make every
-- structural change safe to run again.
do $$
begin
  if to_regclass('public.messages') is null then
    raise exception 'public.messages is required';
  end if;
end $$;

alter table public.messages
  add column if not exists reply_to_message_id bigint;

do $$
declare
  reply_attnum smallint;
  reply_type oid;
  id_attnum smallint;
  existing_constraint record;
begin
  select attnum, atttypid
  into reply_attnum, reply_type
  from pg_attribute
  where attrelid = 'public.messages'::regclass
    and attname = 'reply_to_message_id'
    and not attisdropped;

  select attnum
  into id_attnum
  from pg_attribute
  where attrelid = 'public.messages'::regclass
    and attname = 'id'
    and not attisdropped;

  if reply_type <> 'bigint'::regtype then
    for existing_constraint in
      select constraint_row.conname
      from pg_constraint constraint_row
      where constraint_row.conrelid = 'public.messages'::regclass
        and constraint_row.contype = 'f'
        and reply_attnum = any(constraint_row.conkey)
    loop
      execute format(
        'alter table public.messages drop constraint %I',
        existing_constraint.conname
      );
    end loop;

    alter table public.messages
      alter column reply_to_message_id type bigint
      using reply_to_message_id::bigint;
  end if;

  alter table public.messages
    alter column reply_to_message_id drop not null;

  -- Remove only incompatible single-column foreign keys for this reply field.
  -- A correctly defined constraint is kept in place on repeated execution.
  for existing_constraint in
    select constraint_row.conname
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.messages'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.conkey = array[reply_attnum]::smallint[]
      and not (
        constraint_row.confrelid = 'public.messages'::regclass
        and constraint_row.confkey = array[id_attnum]::smallint[]
        and constraint_row.confdeltype = 'n'
      )
  loop
    execute format(
      'alter table public.messages drop constraint %I',
      existing_constraint.conname
    );
  end loop;

  if not exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.messages'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.conkey = array[reply_attnum]::smallint[]
      and constraint_row.confrelid = 'public.messages'::regclass
      and constraint_row.confkey = array[id_attnum]::smallint[]
      and constraint_row.confdeltype = 'n'
  ) then
    alter table public.messages
      add constraint messages_reply_to_message_id_fkey
      foreign key (reply_to_message_id)
      references public.messages(id)
      on delete set null;
  end if;
end $$;

create index if not exists messages_reply_to_message_id_idx
  on public.messages(reply_to_message_id)
  where reply_to_message_id is not null;

do $$
declare
  reply_attnum smallint;
  id_attnum smallint;
  column_is_valid boolean;
  foreign_key_is_valid boolean;
  index_is_valid boolean;
begin
  select
    attribute_row.attnum,
    attribute_row.atttypid = 'bigint'::regtype
      and not attribute_row.attnotnull
  into reply_attnum, column_is_valid
  from pg_attribute attribute_row
  where attribute_row.attrelid = 'public.messages'::regclass
    and attribute_row.attname = 'reply_to_message_id'
    and not attribute_row.attisdropped;

  if not coalesce(column_is_valid, false) then
    raise exception 'messages.reply_to_message_id has an unexpected definition';
  end if;

  select attribute_row.attnum
  into id_attnum
  from pg_attribute attribute_row
  where attribute_row.attrelid = 'public.messages'::regclass
    and attribute_row.attname = 'id'
    and not attribute_row.attisdropped;

  select exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.messages'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.conkey = array[reply_attnum]::smallint[]
      and constraint_row.confrelid = 'public.messages'::regclass
      and constraint_row.confkey = array[id_attnum]::smallint[]
      and constraint_row.confdeltype = 'n'
      and constraint_row.convalidated
  ) into foreign_key_is_valid;

  if not foreign_key_is_valid then
    raise exception 'messages.reply_to_message_id foreign key has an unexpected definition';
  end if;

  select
    index_row.indisvalid
      and index_row.indisready
      and pg_get_indexdef(index_row.indexrelid)
        ilike '%(reply_to_message_id)%'
      and pg_get_expr(index_row.indpred, index_row.indrelid)
        ilike '%reply_to_message_id is not null%'
  into index_is_valid
  from pg_index index_row
  where index_row.indexrelid =
    to_regclass('public.messages_reply_to_message_id_idx');

  if not coalesce(index_is_valid, false) then
    raise exception 'messages_reply_to_message_id_idx has an unexpected definition';
  end if;
end $$;

-- Make the repaired column visible to PostgREST immediately after commit.
notify pgrst, 'reload schema';

commit;
