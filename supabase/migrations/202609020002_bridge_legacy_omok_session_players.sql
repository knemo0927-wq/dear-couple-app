begin;

-- Legacy deployments require host/guest player columns that are not part of
-- the consolidated schema. Production dependency auditing confirms that these
-- columns are compatibility placeholders: current policies and game RPCs use
-- couple_id plus black/white players. Keep legacy tables insert-compatible
-- without adding the old columns to clean installations.
do $migration$
declare
  host_exists boolean;
  guest_exists boolean;
  host_is_uuid boolean;
  guest_is_uuid boolean;
begin
  select exists (
    select 1
    from pg_attribute
    where attrelid = 'public.omok_sessions'::regclass
      and attname = 'host_user_id'
      and not attisdropped
  ) into host_exists;

  select exists (
    select 1
    from pg_attribute
    where attrelid = 'public.omok_sessions'::regclass
      and attname = 'guest_user_id'
      and not attisdropped
  ) into guest_exists;

  if host_exists <> guest_exists then
    raise exception 'Legacy Omok host/guest columns are incomplete';
  end if;

  if host_exists then
    select atttypid = 'uuid'::regtype
    into host_is_uuid
    from pg_attribute
    where attrelid = 'public.omok_sessions'::regclass
      and attname = 'host_user_id'
      and not attisdropped;

    select atttypid = 'uuid'::regtype
    into guest_is_uuid
    from pg_attribute
    where attrelid = 'public.omok_sessions'::regclass
      and attname = 'guest_user_id'
      and not attisdropped;

    if not coalesce(host_is_uuid, false)
       or not coalesce(guest_is_uuid, false) then
      raise exception 'Legacy Omok host/guest columns must be UUID';
    end if;

    execute $sql$
      create or replace function public.stamp_omok_legacy_session_players()
      returns trigger
      language plpgsql
      set search_path = ''
      as $function$
      begin
        if new.host_user_id is null then
          new.host_user_id := new.black_user_id;
        end if;
        if new.guest_user_id is null then
          new.guest_user_id := new.white_user_id;
        end if;
        return new;
      end;
      $function$
    $sql$;

    execute 'drop trigger if exists '
      || 'omok_sessions_stamp_legacy_players on public.omok_sessions';
    execute 'create trigger omok_sessions_stamp_legacy_players '
      || 'before insert on public.omok_sessions '
      || 'for each row execute function '
      || 'public.stamp_omok_legacy_session_players()';
    execute 'revoke all on function '
      || 'public.stamp_omok_legacy_session_players() '
      || 'from public, anon, authenticated';
  end if;
end;
$migration$;

do $$
declare
  host_exists boolean;
  guest_exists boolean;
  bridge_is_valid boolean;
begin
  select exists (
    select 1
    from pg_attribute
    where attrelid = 'public.omok_sessions'::regclass
      and attname = 'host_user_id'
      and atttypid = 'uuid'::regtype
      and not attisdropped
  ) into host_exists;

  select exists (
    select 1
    from pg_attribute
    where attrelid = 'public.omok_sessions'::regclass
      and attname = 'guest_user_id'
      and atttypid = 'uuid'::regtype
      and not attisdropped
  ) into guest_exists;

  if host_exists <> guest_exists then
    raise exception 'Legacy Omok player contract is asymmetric';
  end if;

  if host_exists then
    select exists (
      select 1
      from pg_trigger trigger_row
      join pg_proc function_row on function_row.oid = trigger_row.tgfoid
      join pg_namespace namespace_row
        on namespace_row.oid = function_row.pronamespace
      where trigger_row.tgrelid = 'public.omok_sessions'::regclass
        and trigger_row.tgname = 'omok_sessions_stamp_legacy_players'
        and not trigger_row.tgisinternal
        and trigger_row.tgenabled <> 'D'
        and namespace_row.nspname = 'public'
        and function_row.proname = 'stamp_omok_legacy_session_players'
    ) into bridge_is_valid;

    if not bridge_is_valid then
      raise exception 'Legacy Omok player bridge was not installed';
    end if;

    if has_function_privilege(
      'anon',
      'public.stamp_omok_legacy_session_players()',
      'execute'
    ) or has_function_privilege(
      'authenticated',
      'public.stamp_omok_legacy_session_players()',
      'execute'
    ) then
      raise exception 'Legacy Omok player bridge has unsafe execute grants';
    end if;
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;
