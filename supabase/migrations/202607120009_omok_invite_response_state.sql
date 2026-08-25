begin;

-- A durable sender key lets the inviter restore the latest push-invite state
-- after navigation, process restart, or sign-in on another device.
alter table public.omok_invites
  add column if not exists sender_user_id uuid;

do $$
begin
  -- Backfill from a legacy author column when one exists. Different deployed
  -- revisions used different names, so each reference is kept in dynamic SQL.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'omok_invites'
      and column_name = 'inviter_user_id'
  ) then
    execute '
      update public.omok_invites
      set sender_user_id = inviter_user_id
      where sender_user_id is null
    ';
  elsif exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'omok_invites'
      and column_name = 'created_by'
  ) then
    execute '
      update public.omok_invites
      set sender_user_id = created_by
      where sender_user_id is null
    ';
  elsif exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'omok_invites'
      and column_name = 'user_id'
  ) then
    execute '
      update public.omok_invites
      set sender_user_id = user_id
      where sender_user_id is null
    ';
  end if;
end;
$$;

-- A push invite always targets the other profile in the same couple, which
-- provides a deterministic fallback for legacy rows without an author field.
update public.omok_invites invite
set sender_user_id = sender.user_id
from public.profiles recipient,
     public.profiles sender
where invite.sender_user_id is null
  and invite.invite_type = 'push'
  and invite.recipient_user_id = recipient.user_id
  and sender.couple_id = recipient.couple_id
  and sender.user_id <> recipient.user_id;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'omok_invites_sender_user_id_fkey'
      and conrelid = 'public.omok_invites'::regclass
  ) then
    alter table public.omok_invites
      add constraint omok_invites_sender_user_id_fkey
      foreign key (sender_user_id)
      references auth.users(id)
      on delete cascade;
  end if;
end;
$$;

create index if not exists omok_invites_sender_created_idx
  on public.omok_invites(sender_user_id, invite_type, created_at desc);

create or replace function public.stamp_omok_invite_sender()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- An authenticated caller can never forge another sender. Service-role
  -- maintenance may preserve an explicitly supplied value when auth.uid()
  -- is intentionally absent.
  if auth.uid() is not null then
    new.sender_user_id := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists omok_invites_stamp_sender on public.omok_invites;
create trigger omok_invites_stamp_sender
before insert on public.omok_invites
for each row execute function public.stamp_omok_invite_sender();

alter table public.omok_invites enable row level security;
drop policy if exists omok_invites_select_response_participants
  on public.omok_invites;
create policy omok_invites_select_response_participants
  on public.omok_invites for select
  using (
    sender_user_id = auth.uid()
    or recipient_user_id = auth.uid()
  );

-- Extend the deployed invite state machine with an explicit terminal reject
-- state. The table historically used open/used/expired.
do $$
declare
  target_constraint record;
begin
  for target_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.omok_invites'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop
    execute format(
      'alter table public.omok_invites drop constraint %I',
      target_constraint.conname
    );
  end loop;
end;
$$;

alter table public.omok_invites
  add constraint omok_invites_status_response_check
  check (
    status in (
      'open',
      'used',
      'expired',
      'rejected',
      'declined',
      'cancelled'
    )
  );

create or replace function public.expire_omok_invite_if_needed(
  target_invite_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target_invite public.omok_invites%rowtype;
begin
  select * into target_invite
  from public.omok_invites
  where id = target_invite_id
  for update;

  if not found then
    raise exception 'OMOK_INVITE_NOT_FOUND';
  end if;
  if auth.uid() is null or (
    target_invite.sender_user_id is distinct from auth.uid()
    and target_invite.recipient_user_id is distinct from auth.uid()
  ) then
    raise exception 'OMOK_INVITE_FORBIDDEN';
  end if;

  if target_invite.status = 'open'
     and target_invite.expires_at <= now() then
    update public.omok_invites
    set status = 'expired'
    where id = target_invite_id;
    target_invite.status := 'expired';

    delete from public.notification_jobs
    where dedupe_key = target_invite.recipient_user_id::text
        || ':omok-invite:' || target_invite.id::text
      and status in ('pending', 'failed');
  end if;

  return target_invite.status;
end;
$$;

revoke all on function public.expire_omok_invite_if_needed(uuid) from public;
grant execute on function public.expire_omok_invite_if_needed(uuid)
  to authenticated;

create or replace function public.reject_omok_push_invite(
  target_invite_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target_invite public.omok_invites%rowtype;
begin
  select * into target_invite
  from public.omok_invites
  where id = target_invite_id
  for update;

  if not found then
    raise exception 'OMOK_INVITE_NOT_FOUND';
  end if;
  if auth.uid() is null
     or target_invite.recipient_user_id is distinct from auth.uid() then
    raise exception 'OMOK_INVITE_FORBIDDEN';
  end if;
  if target_invite.invite_type <> 'push' then
    raise exception 'OMOK_PUSH_INVITE_REQUIRED';
  end if;
  if target_invite.status = 'rejected' then
    return 'rejected';
  end if;
  if target_invite.status <> 'open' then
    raise exception 'OMOK_INVITE_NOT_OPEN';
  end if;
  if target_invite.expires_at <= now() then
    update public.omok_invites
    set status = 'expired'
    where id = target_invite_id;

    delete from public.notification_jobs
    where dedupe_key = target_invite.recipient_user_id::text
        || ':omok-invite:' || target_invite.id::text
      and status in ('pending', 'failed');
    return 'expired';
  end if;

  update public.omok_invites
  set status = 'rejected'
  where id = target_invite_id;

  -- The existing insert-only notification trigger remains the sole producer
  -- and still checks notification_preferences.game_enabled. Remove only jobs
  -- that have not begun delivery so a late worker retry cannot surface a
  -- rejected invitation.
  delete from public.notification_jobs
  where dedupe_key = target_invite.recipient_user_id::text
      || ':omok-invite:' || target_invite.id::text
    and status in ('pending', 'failed');

  return 'rejected';
end;
$$;

revoke all on function public.reject_omok_push_invite(uuid) from public;
grant execute on function public.reject_omok_push_invite(uuid)
  to authenticated;

create or replace function public.expire_open_omok_invites()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  changed_count integer;
begin
  update public.omok_invites
  set status = 'expired'
  where status = 'open'
    and expires_at <= now();
  get diagnostics changed_count = row_count;

  delete from public.notification_jobs job
  using public.omok_invites invite
  where invite.status = 'expired'
    and job.dedupe_key = invite.recipient_user_id::text
        || ':omok-invite:' || invite.id::text
    and job.status in ('pending', 'failed');

  return changed_count;
end;
$$;

revoke all on function public.expire_open_omok_invites() from public;

-- pg_cron is installed by the notification scheduler migration. Guard the
-- setup so local databases without the extension can still apply this file;
-- open screens also call expire_omok_invite_if_needed at the exact deadline.
do $$
declare
  existing_job_id bigint;
begin
  if to_regclass('cron.job') is null then
    return;
  end if;

  select jobid into existing_job_id
  from cron.job
  where jobname = 'dear-omok-invite-expiry'
  limit 1;

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;

  perform cron.schedule(
    'dear-omok-invite-expiry',
    '* * * * *',
    $command$select public.expire_open_omok_invites()$command$
  );
end;
$$;

commit;
