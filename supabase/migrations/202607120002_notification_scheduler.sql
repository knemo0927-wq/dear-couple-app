begin;

-- Durable outbox consumed by the existing push worker/Edge Function. A unique
-- dedupe key makes retries and overlapping scheduler runs safe.
create table if not exists public.notification_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  couple_id uuid references public.couples(id) on delete cascade,
  category text not null,
  event_key text not null,
  event_date date not null,
  scheduled_for timestamptz not null,
  timezone text not null,
  deliver_silently boolean not null default false,
  route text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  attempts integer not null default 0,
  last_error text,
  sent_at timestamptz,
  dedupe_key text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (category in ('anniversary', 'message', 'image', 'game')),
  check (status in ('pending', 'processing', 'sent', 'failed'))
);

create index if not exists notification_jobs_dispatch_idx
  on public.notification_jobs(status, scheduled_for, created_at)
  where status in ('pending', 'failed');

alter table public.notification_jobs enable row level security;
drop policy if exists notification_jobs_select_own
  on public.notification_jobs;
create policy notification_jobs_select_own
  on public.notification_jobs for select
  using (user_id = auth.uid());

-- Enqueues custom anniversaries and automatic 100-day/year milestones. This
-- function only creates jobs; the push worker owns APNs/FCM delivery and marks
-- them sent. It is safe to call more than once per minute/day.
create or replace function public.enqueue_due_anniversary_notifications(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  pref record;
  local_now timestamp without time zone;
  target_date date;
  scheduled_at timestamptz;
  inserted_count integer;
  total_inserted integer := 0;
begin
  for pref in
    select
      p.user_id,
      coalesce(np.timezone, 'Asia/Seoul') as timezone,
      coalesce(np.anniversary_hour, 9) as anniversary_hour,
      coalesce(np.quiet_enabled, false) as quiet_enabled,
      coalesce(np.quiet_start, '22:00:00'::time) as quiet_start,
      coalesce(np.quiet_end, '07:00:00'::time) as quiet_end,
      p.couple_id
    from public.profiles p
    left join public.notification_preferences np on np.user_id = p.user_id
    where coalesce(np.anniversary_enabled, true)
      and p.couple_id is not null
  loop
    begin
      local_now := p_now at time zone pref.timezone;
    exception when invalid_parameter_value then
      -- Invalid IANA zones never fall back silently to the database timezone.
      continue;
    end;

    -- Custom entries can choose their own reminder hour and lead time.
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
    )
    select
      pref.user_id,
      pref.couple_id,
      'anniversary',
      'custom:' || a.id::text,
      case
        when a.repeat_rule = 'yearly'
          then local_now::date + a.reminder_days_before
        else a.event_date
      end,
      (local_now::date + make_time(a.reminder_hour, 0, 0))
        at time zone pref.timezone,
      pref.timezone,
      pref.quiet_enabled and (
        case
          when pref.quiet_start <= pref.quiet_end then
            local_now::time >= pref.quiet_start
            and local_now::time < pref.quiet_end
          else
            local_now::time >= pref.quiet_start
            or local_now::time < pref.quiet_end
        end
      ),
      '/anniversary-reminders?item=' || a.id::text,
      jsonb_build_object(
        'anniversary_id', a.id,
        'title', a.title,
        'event_date', case
          when a.repeat_rule = 'yearly'
            then local_now::date + a.reminder_days_before
          else a.event_date
        end
      ),
      pref.user_id::text || ':custom:' || a.id::text || ':' ||
        local_now::date::text
    from public.anniversaries a
    where a.couple_id = pref.couple_id
      and a.reminder_enabled
      and (
        (local_now::date + make_time(a.reminder_hour, 0, 0))
          at time zone pref.timezone
      ) <= p_now
      and (
        (local_now::date + make_time(a.reminder_hour, 0, 0))
          at time zone pref.timezone
      ) > p_now - interval '24 hours'
      and (
        (
          a.repeat_rule = 'none'
          and a.event_date - a.reminder_days_before = local_now::date
        )
        or (
          a.repeat_rule = 'yearly'
          and local_now::date + a.reminder_days_before >= a.event_date
          and public.anniversary_occurrence_date(
            a.event_date,
            local_now::date + a.reminder_days_before
          ) = (
            local_now::date + a.reminder_days_before
          )
        )
      )
    on conflict (dedupe_key) do nothing;
    get diagnostics inserted_count = row_count;
    total_inserted := total_inserted + inserted_count;

    -- Automatic milestones use the user-level anniversary hour.
    target_date := local_now::date;
    scheduled_at := (
      local_now::date + make_time(pref.anniversary_hour, 0, 0)
    ) at time zone pref.timezone;

    if scheduled_at > p_now or scheduled_at <= p_now - interval '24 hours' then
      continue;
    end if;

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
    )
    select
      pref.user_id,
      pref.couple_id,
      'anniversary',
      milestone.event_key,
      target_date,
      scheduled_at,
      pref.timezone,
      pref.quiet_enabled and (
        case
          when pref.quiet_start <= pref.quiet_end then
            local_now::time >= pref.quiet_start
            and local_now::time < pref.quiet_end
          else
            local_now::time >= pref.quiet_start
            or local_now::time < pref.quiet_end
        end
      ),
      '/anniversary-reminders',
      milestone.payload,
      pref.user_id::text || ':' || milestone.event_key || ':' ||
        target_date::text
    from public.couples c
    cross join lateral (
      select
        'days:' || ((target_date - c.anniversary_date) + 1)::text as event_key,
        jsonb_build_object(
          'kind', 'hundred_days',
          'day_count', (target_date - c.anniversary_date) + 1,
          'event_date', target_date
        ) as payload
      where c.anniversary_date is not null
        and (target_date - c.anniversary_date) + 1 >= 100
        and mod((target_date - c.anniversary_date) + 1, 100) = 0

      union all

      select
        'years:' || (extract(year from target_date)::integer -
          extract(year from c.anniversary_date)::integer)::text,
        jsonb_build_object(
          'kind', 'yearly',
          'year_count', extract(year from target_date)::integer -
            extract(year from c.anniversary_date)::integer,
          'event_date', target_date
        )
      where c.anniversary_date is not null
        and target_date > c.anniversary_date
        and public.anniversary_occurrence_date(
          c.anniversary_date,
          target_date
        ) = target_date
    ) milestone
    where c.id = pref.couple_id
    on conflict (dedupe_key) do nothing;
    get diagnostics inserted_count = row_count;
    total_inserted := total_inserted + inserted_count;
  end loop;

  return total_inserted;
end;
$$;

revoke all on function public.enqueue_due_anniversary_notifications(timestamptz)
  from public, anon, authenticated;
grant execute on function public.enqueue_due_anniversary_notifications(timestamptz)
  to service_role;

commit;
