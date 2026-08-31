begin;

create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if to_regclass('public.omok_sessions') is null
     or to_regclass('public.omok_invites') is null
     or to_regclass('public.omok_notifications') is null
     or to_regclass('public.profiles') is null then
    raise exception 'Omok tables are required';
  end if;
end $$;

-- Existing sessions retain their original colors. These nullable fields only
-- explain how sessions created after this migration received their stones.
alter table public.omok_sessions
  add column if not exists stone_assignment_reason text,
  add column if not exists stone_assignment_source_session_id uuid;

alter table public.omok_sessions
  drop constraint if exists omok_sessions_stone_assignment_reason_check,
  drop constraint if exists omok_sessions_stone_assignment_source_session_id_fkey;

alter table public.omok_sessions
  add constraint omok_sessions_stone_assignment_reason_check
    check (
      stone_assignment_reason is null
      or stone_assignment_reason in ('previous_result', 'random_no_history')
    ),
  add constraint omok_sessions_stone_assignment_source_session_id_fkey
    foreign key (stone_assignment_source_session_id)
    references public.omok_sessions(id)
    on delete set null;

create index if not exists omok_sessions_assignment_source_idx
  on public.omok_sessions(stone_assignment_source_session_id)
  where stone_assignment_source_session_id is not null;

-- This partial index supports the exact history lookup used by the assignment
-- resolver without changing any existing session or rematch uniqueness rule.
create index if not exists omok_sessions_decisive_history_idx
  on public.omok_sessions(couple_id, finished_at desc, created_at desc)
  where finished_at is not null
    and winner_user_id is not null
    and status in (
      'black_win',
      'white_win',
      'black_timeout_win',
      'white_timeout_win',
      'black_resign_win',
      'white_resign_win'
    );

-- Resolve colors once on the server. Draws and cancelled sessions are not
-- decisive, so the latest earlier win/loss remains the source. If the pair has
-- never completed a decisive game, pgcrypto supplies a 50:50 assignment.
create or replace function public.resolve_omok_stone_assignment(
  target_couple_id uuid,
  target_player_a_user_id uuid,
  target_player_b_user_id uuid
)
returns table (
  assigned_black_user_id uuid,
  assigned_white_user_id uuid,
  assignment_reason text,
  assignment_source_session_id uuid
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  source_session public.omok_sessions%rowtype;
begin
  select session.*
  into source_session
  from public.omok_sessions session
  where session.couple_id = target_couple_id
    and session.finished_at is not null
    and session.winner_user_id in (
      target_player_a_user_id,
      target_player_b_user_id
    )
    and session.status in (
      'black_win',
      'white_win',
      'black_timeout_win',
      'white_timeout_win',
      'black_resign_win',
      'white_resign_win'
    )
    and (
      (
        session.black_user_id = target_player_a_user_id
        and session.white_user_id = target_player_b_user_id
      )
      or (
        session.black_user_id = target_player_b_user_id
        and session.white_user_id = target_player_a_user_id
      )
    )
  order by
    session.finished_at desc,
    session.created_at desc,
    session.id desc
  limit 1;

  if found then
    return query
    select
      case
        when source_session.winner_user_id = target_player_a_user_id
          then target_player_b_user_id
        else target_player_a_user_id
      end,
      source_session.winner_user_id,
      'previous_result'::text,
      source_session.id;
    return;
  end if;

  if pg_catalog.get_byte(extensions.gen_random_bytes(1), 0) % 2 = 0 then
    return query
    select
      target_player_a_user_id,
      target_player_b_user_id,
      'random_no_history'::text,
      null::uuid;
  else
    return query
    select
      target_player_b_user_id,
      target_player_a_user_id,
      'random_no_history'::text,
      null::uuid;
  end if;
end;
$$;

-- Keep the historical internal signature so already-deployed public RPCs and
-- any in-flight PostgREST schema cache remain compatible. Its second and third
-- arguments are now treated as the two participants, not predetermined colors.
create or replace function public.create_omok_session_internal(
  target_couple_id uuid,
  target_black_user_id uuid,
  target_white_user_id uuid,
  target_rematch_of uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_session_id uuid;
  resolved_black_user_id uuid;
  resolved_white_user_id uuid;
  resolved_assignment_reason text;
  resolved_source_session_id uuid;
begin
  if target_black_user_id = target_white_user_id then
    raise exception 'OMOK_PLAYERS_MUST_DIFFER';
  end if;
  if not exists (
    select 1
    from public.profiles profile
    where profile.couple_id = target_couple_id
      and profile.user_id = target_black_user_id
  ) or not exists (
    select 1
    from public.profiles profile
    where profile.couple_id = target_couple_id
      and profile.user_id = target_white_user_id
  ) then
    raise exception 'OMOK_PLAYERS_NOT_IN_COUPLE';
  end if;

  if target_rematch_of is not null and not exists (
    select 1
    from public.omok_sessions session
    where session.id = target_rematch_of
      and session.couple_id = target_couple_id
      and (
        (
          session.black_user_id = target_black_user_id
          and session.white_user_id = target_white_user_id
        )
        or (
          session.black_user_id = target_white_user_id
          and session.white_user_id = target_black_user_id
        )
      )
  ) then
    raise exception 'OMOK_REMATCH_SESSION_MISMATCH';
  end if;

  -- Serialize color resolution and insertion per couple so concurrent invite
  -- and rematch creation cannot observe different committed history snapshots.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_couple_id::text, 0)
  );

  select
    assignment.assigned_black_user_id,
    assignment.assigned_white_user_id,
    assignment.assignment_reason,
    assignment.assignment_source_session_id
  into
    resolved_black_user_id,
    resolved_white_user_id,
    resolved_assignment_reason,
    resolved_source_session_id
  from public.resolve_omok_stone_assignment(
    target_couple_id,
    target_black_user_id,
    target_white_user_id
  ) assignment;

  if resolved_black_user_id is null or resolved_white_user_id is null then
    raise exception 'OMOK_STONE_ASSIGNMENT_FAILED';
  end if;

  insert into public.omok_sessions (
    couple_id,
    black_user_id,
    white_user_id,
    current_turn_user_id,
    status,
    turn_expires_at,
    rematch_of_session_id,
    created_by,
    stone_assignment_reason,
    stone_assignment_source_session_id
  ) values (
    target_couple_id,
    resolved_black_user_id,
    resolved_white_user_id,
    resolved_black_user_id,
    'playing',
    pg_catalog.now() + interval '30 seconds',
    target_rematch_of,
    auth.uid(),
    resolved_assignment_reason,
    resolved_source_session_id
  )
  returning id into created_session_id;

  return created_session_id;
end;
$$;

-- Code-invite joins continue to lock and consume the invite exactly once, but
-- the participants are handed to the centralized assignment function.
create or replace function public.join_omok_with_invite_code(
  target_invite_code text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_invite public.omok_invites%rowtype;
  joining_couple_id uuid;
  sender_couple_id uuid;
  created_session_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select invite.*
  into target_invite
  from public.omok_invites invite
  where invite.invite_code = pg_catalog.upper(
    pg_catalog.btrim(target_invite_code)
  )
  for update;

  if not found then raise exception 'OMOK_INVITE_NOT_FOUND'; end if;
  if target_invite.status <> 'open' then
    raise exception 'OMOK_INVITE_NOT_OPEN';
  end if;
  if target_invite.expires_at <= pg_catalog.now() then
    update public.omok_invites
    set status = 'expired'
    where id = target_invite.id;
    raise exception 'OMOK_INVITE_EXPIRED';
  end if;
  if target_invite.sender_user_id = auth.uid() then
    raise exception 'OMOK_SELF_JOIN_NOT_ALLOWED';
  end if;

  select profile.couple_id
  into joining_couple_id
  from public.profiles profile
  where profile.user_id = auth.uid();

  select profile.couple_id
  into sender_couple_id
  from public.profiles profile
  where profile.user_id = target_invite.sender_user_id;

  if joining_couple_id is null
     or joining_couple_id is distinct from sender_couple_id then
    raise exception 'OMOK_INVITE_COUPLE_MISMATCH';
  end if;

  created_session_id := public.create_omok_session_internal(
    joining_couple_id,
    target_invite.sender_user_id,
    auth.uid(),
    null
  );

  update public.omok_invites
  set
    status = 'used',
    recipient_user_id = auth.uid(),
    session_id = created_session_id
  where id = target_invite.id;

  return created_session_id;
end;
$$;

-- Push-invite acceptance keeps its existing idempotent used-invite response.
create or replace function public.accept_omok_push_invite(
  target_invite_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_invite public.omok_invites%rowtype;
  target_couple_id uuid;
  sender_couple_id uuid;
  created_session_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select invite.*
  into target_invite
  from public.omok_invites invite
  where invite.id = target_invite_id
  for update;

  if not found then raise exception 'OMOK_INVITE_NOT_FOUND'; end if;
  if target_invite.invite_type <> 'push'
     or target_invite.recipient_user_id is distinct from auth.uid() then
    raise exception 'OMOK_INVITE_FORBIDDEN';
  end if;
  if target_invite.status = 'used'
     and target_invite.session_id is not null then
    return target_invite.session_id;
  end if;
  if target_invite.status <> 'open' then
    raise exception 'OMOK_INVITE_NOT_OPEN';
  end if;
  if target_invite.expires_at <= pg_catalog.now() then
    update public.omok_invites
    set status = 'expired'
    where id = target_invite.id;
    raise exception 'OMOK_INVITE_EXPIRED';
  end if;

  select profile.couple_id
  into target_couple_id
  from public.profiles profile
  where profile.user_id = auth.uid();

  select profile.couple_id
  into sender_couple_id
  from public.profiles profile
  where profile.user_id = target_invite.sender_user_id;

  if target_couple_id is null
     or target_couple_id is distinct from sender_couple_id then
    raise exception 'OMOK_INVITE_COUPLE_MISMATCH';
  end if;

  created_session_id := public.create_omok_session_internal(
    target_couple_id,
    target_invite.sender_user_id,
    auth.uid(),
    null
  );

  update public.omok_invites
  set
    status = 'used',
    session_id = created_session_id
  where id = target_invite.id;

  return created_session_id;
end;
$$;

-- Rematches retain the parent row lock, one-child unique index, and existing
-- notification behavior. Color order is no longer manually swapped here.
create or replace function public.create_omok_rematch(target_session_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_session public.omok_sessions%rowtype;
  existing_session_id uuid;
  created_session_id uuid;
  recipient_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;

  select session.*
  into target_session
  from public.omok_sessions session
  where session.id = target_session_id
  for update;

  if not found then raise exception 'OMOK_SESSION_NOT_FOUND'; end if;
  if auth.uid() not in (
    target_session.black_user_id,
    target_session.white_user_id
  ) then
    raise exception 'OMOK_SESSION_FORBIDDEN';
  end if;
  if target_session.status = 'playing' then
    raise exception 'OMOK_SESSION_STILL_PLAYING';
  end if;

  select session.id
  into existing_session_id
  from public.omok_sessions session
  where session.rematch_of_session_id = target_session_id;

  if existing_session_id is not null then
    return existing_session_id;
  end if;

  created_session_id := public.create_omok_session_internal(
    target_session.couple_id,
    target_session.black_user_id,
    target_session.white_user_id,
    target_session.id
  );

  recipient_id := case
    when auth.uid() = target_session.black_user_id
      then target_session.white_user_id
    else target_session.black_user_id
  end;

  insert into public.omok_notifications (
    recipient_user_id,
    session_id,
    notification_type,
    actor_user_id
  ) values (
    recipient_id,
    created_session_id,
    'rematch_created',
    auth.uid()
  );

  return created_session_id;
end;
$$;

-- Internal assignment functions must never be callable through PostgREST.
revoke all on function public.resolve_omok_stone_assignment(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.create_omok_session_internal(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;

-- Restore the existing public RPC contract explicitly after replacement.
revoke all on function public.join_omok_with_invite_code(text)
  from public, anon, authenticated;
revoke all on function public.accept_omok_push_invite(uuid)
  from public, anon, authenticated;
revoke all on function public.create_omok_rematch(uuid)
  from public, anon, authenticated;

grant execute on function public.join_omok_with_invite_code(text)
  to authenticated;
grant execute on function public.accept_omok_push_invite(uuid)
  to authenticated;
grant execute on function public.create_omok_rematch(uuid)
  to authenticated;

notify pgrst, 'reload schema';

commit;
