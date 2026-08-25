begin;

alter table public.notification_jobs
  add column if not exists locked_at timestamptz,
  add column if not exists locked_by text,
  add column if not exists next_attempt_at timestamptz,
  add column if not exists read_at timestamptz;

alter table public.notification_jobs
  drop constraint if exists notification_jobs_status_check;
alter table public.notification_jobs
  add constraint notification_jobs_status_check
  check (status in ('pending', 'processing', 'sent', 'failed', 'cancelled'));

create or replace function public.touch_notification_job_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists notification_jobs_touch_updated_at
  on public.notification_jobs;
create trigger notification_jobs_touch_updated_at
before update on public.notification_jobs
for each row execute function public.touch_notification_job_updated_at();

create or replace function public.notification_is_quiet(
  target_user_id uuid,
  target_time timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select np.quiet_enabled and (
      case
        when np.quiet_start <= np.quiet_end then
          (target_time at time zone np.timezone)::time >= np.quiet_start
          and (target_time at time zone np.timezone)::time < np.quiet_end
        else
          (target_time at time zone np.timezone)::time >= np.quiet_start
          or (target_time at time zone np.timezone)::time < np.quiet_end
      end
    )
    from public.notification_preferences np
    where np.user_id = target_user_id
  ), false);
$$;

revoke all on function public.notification_is_quiet(uuid, timestamptz)
  from public, anon, authenticated;

create or replace function public.enqueue_message_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient record;
  message_category text;
  sender_name text;
begin
  if new.image_path is not null and length(trim(new.image_path)) > 0 then
    message_category := 'image';
  else
    message_category := 'message';
  end if;

  select nullif(trim(nickname), '') into sender_name
  from public.profiles
  where user_id = new.sender_id;

  for recipient in
    select
      p.user_id,
      coalesce(np.timezone, 'Asia/Seoul') as timezone
    from public.profiles p
    left join public.notification_preferences np on np.user_id = p.user_id
    where p.couple_id = new.couple_id
      and p.user_id <> new.sender_id
      and case
        when message_category = 'image' then coalesce(np.image_enabled, true)
        else coalesce(np.message_enabled, true)
      end
  loop
    insert into public.notification_jobs (
      user_id,
      couple_id,
      category,
      event_key,
      event_date,
      scheduled_for,
      timezone,
      deliver_silently,
      route,
      payload,
      dedupe_key
    ) values (
      recipient.user_id,
      new.couple_id,
      message_category,
      'message:' || new.id::text,
      (new.created_at at time zone recipient.timezone)::date,
      new.created_at,
      recipient.timezone,
      public.notification_is_quiet(recipient.user_id, new.created_at),
      '/chat/' || new.couple_id::text,
      jsonb_build_object(
        'message_id', new.id,
        'sender_id', new.sender_id,
        'title', coalesce(sender_name, 'Dear'),
        'body', case
          when message_category = 'image' then '사진을 보냈어요.'
          else left(coalesce(new.body, '새 메시지가 도착했어요.'), 120)
        end
      ),
      recipient.user_id::text || ':message:' || new.id::text
    )
    on conflict (dedupe_key) do nothing;
  end loop;
  return new;
end;
$$;

drop trigger if exists messages_enqueue_notification on public.messages;
create trigger messages_enqueue_notification
after insert on public.messages
for each row execute function public.enqueue_message_notification();

create or replace function public.enqueue_omok_invite_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_couple_id uuid;
  target_timezone text;
  enabled boolean;
begin
  if new.invite_type <> 'push' or new.recipient_user_id is null then
    return new;
  end if;

  select
    p.couple_id,
    coalesce(np.timezone, 'Asia/Seoul'),
    coalesce(np.game_enabled, true)
  into target_couple_id, target_timezone, enabled
  from public.profiles p
  left join public.notification_preferences np on np.user_id = p.user_id
  where p.user_id = new.recipient_user_id;

  if not coalesce(enabled, true) then return new; end if;
  target_timezone := coalesce(target_timezone, 'Asia/Seoul');

  insert into public.notification_jobs (
    user_id,
    couple_id,
    category,
    event_key,
    event_date,
    scheduled_for,
    timezone,
    deliver_silently,
    route,
    payload,
    dedupe_key
  ) values (
    new.recipient_user_id,
    target_couple_id,
    'game',
    'omok-invite:' || new.id::text,
    (now() at time zone target_timezone)::date,
    now(),
    target_timezone,
    public.notification_is_quiet(new.recipient_user_id, now()),
    '/omok/invite/' || new.id::text,
    jsonb_build_object(
      'invite_id', new.id,
      'expires_at', new.expires_at,
      'title', 'Dear 오목',
      'body', '오목 초대가 도착했어요.'
    ),
    new.recipient_user_id::text || ':omok-invite:' || new.id::text
  )
  on conflict (dedupe_key) do nothing;
  return new;
end;
$$;

drop trigger if exists omok_invites_enqueue_push on public.omok_invites;
create trigger omok_invites_enqueue_push
after insert on public.omok_invites
for each row execute function public.enqueue_omok_invite_notification();

create or replace function public.enqueue_omok_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_couple_id uuid;
  target_timezone text;
  enabled boolean;
begin
  select couple_id into target_couple_id
  from public.omok_sessions
  where id = new.session_id;

  select
    coalesce(np.timezone, 'Asia/Seoul'),
    coalesce(np.game_enabled, true)
  into target_timezone, enabled
  from public.profiles p
  left join public.notification_preferences np on np.user_id = p.user_id
  where p.user_id = new.recipient_user_id;

  if not coalesce(enabled, true) then return new; end if;
  target_timezone := coalesce(target_timezone, 'Asia/Seoul');

  insert into public.notification_jobs (
    user_id,
    couple_id,
    category,
    event_key,
    event_date,
    scheduled_for,
    timezone,
    deliver_silently,
    route,
    payload,
    dedupe_key
  ) values (
    new.recipient_user_id,
    target_couple_id,
    'game',
    'omok:' || new.id::text,
    (new.created_at at time zone target_timezone)::date,
    new.created_at,
    target_timezone,
    public.notification_is_quiet(new.recipient_user_id, new.created_at),
    '/omok/' || new.session_id::text,
    jsonb_build_object(
      'notification_id', new.id,
      'session_id', new.session_id,
      'notification_type', new.notification_type,
      'actor_user_id', new.actor_user_id,
      'title', 'Dear 오목',
      'body', case
        when new.notification_type in ('rechallenge_created', 'rematch_created')
          then '재대결 신청이 도착했어요.'
        else '오목 초대가 도착했어요.'
      end
    ),
    new.recipient_user_id::text || ':omok:' || new.id::text
  )
  on conflict (dedupe_key) do nothing;
  return new;
end;
$$;

drop trigger if exists omok_notifications_enqueue_push
  on public.omok_notifications;
create trigger omok_notifications_enqueue_push
after insert on public.omok_notifications
for each row execute function public.enqueue_omok_notification();

create or replace function public.claim_notification_jobs(
  worker_id text,
  batch_size integer default 50
)
returns setof public.notification_jobs
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('request.jwt.claim.role', true) <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  return query
  with candidates as (
    select j.id
    from public.notification_jobs j
    where (
        j.status in ('pending', 'failed')
        or (j.status = 'processing' and j.locked_at < now() - interval '5 minutes')
      )
      and j.scheduled_for <= now()
      and coalesce(j.next_attempt_at, j.scheduled_for) <= now()
      and j.attempts < 8
    order by j.scheduled_for, j.created_at
    for update skip locked
    limit greatest(1, least(batch_size, 100))
  )
  update public.notification_jobs j
  set status = 'processing',
      locked_at = now(),
      locked_by = worker_id
  from candidates c
  where j.id = c.id
  returning j.*;
end;
$$;

create or replace function public.finish_notification_job(
  target_job_id uuid,
  succeeded boolean,
  error_message text default null,
  cancel_job boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if current_setting('request.jwt.claim.role', true) <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;

  update public.notification_jobs
  set status = case
        when cancel_job then 'cancelled'
        when succeeded then 'sent'
        else 'failed'
      end,
      attempts = attempts + case when succeeded or cancel_job then 0 else 1 end,
      last_error = case when succeeded or cancel_job then null else left(error_message, 1000) end,
      sent_at = case when succeeded then now() else sent_at end,
      next_attempt_at = case
        when succeeded or cancel_job then null
        else now() + make_interval(
          mins => least(360, (power(2, least(attempts + 1, 8))::integer))
        )
      end,
      locked_at = null,
      locked_by = null
  where id = target_job_id;
end;
$$;

revoke all on function public.claim_notification_jobs(text, integer)
  from public, anon, authenticated;
revoke all on function public.finish_notification_job(uuid, boolean, text, boolean)
  from public, anon, authenticated;
grant execute on function public.claim_notification_jobs(text, integer)
  to service_role;
grant execute on function public.finish_notification_job(uuid, boolean, text, boolean)
  to service_role;

create or replace function public.mark_notification_jobs_read(
  target_job_ids uuid[]
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.notification_jobs
  set read_at = coalesce(read_at, now())
  where user_id = auth.uid()
    and id = any(target_job_ids);
$$;

revoke all on function public.mark_notification_jobs_read(uuid[]) from public;
grant execute on function public.mark_notification_jobs_read(uuid[])
  to authenticated;

commit;
