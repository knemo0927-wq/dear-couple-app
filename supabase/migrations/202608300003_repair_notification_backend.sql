begin;

create extension if not exists pgcrypto with schema extensions;

-- Production can be missing the notification migrations even when the client
-- routes are already released. Rebuild only the two client-facing tables here
-- so this repair does not depend on the optional worker/cron rollout.
create table if not exists public.notification_preferences (
  user_id uuid primary key
    references auth.users(id) on delete cascade,
  message_enabled boolean not null default true,
  image_enabled boolean not null default true,
  anniversary_enabled boolean not null default true,
  game_enabled boolean not null default true,
  quiet_enabled boolean not null default false,
  quiet_start time not null default '22:00:00',
  quiet_end time not null default '07:00:00',
  anniversary_hour smallint not null default 9,
  timezone text not null default 'Asia/Seoul',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_preferences_anniversary_hour_check
    check (anniversary_hour between 0 and 23)
);

-- These additions make the repair safe for environments where an incomplete
-- preferences table was created manually or by a partially applied migration.
alter table public.notification_preferences
  add column if not exists user_id uuid,
  add column if not exists message_enabled boolean default true,
  add column if not exists image_enabled boolean default true,
  add column if not exists anniversary_enabled boolean default true,
  add column if not exists game_enabled boolean default true,
  add column if not exists quiet_enabled boolean default false,
  add column if not exists quiet_start time default '22:00:00',
  add column if not exists quiet_end time default '07:00:00',
  add column if not exists anniversary_hour smallint default 9,
  add column if not exists timezone text default 'Asia/Seoul',
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

update public.notification_preferences
set
  message_enabled = coalesce(message_enabled, true),
  image_enabled = coalesce(image_enabled, true),
  anniversary_enabled = coalesce(anniversary_enabled, true),
  game_enabled = coalesce(game_enabled, true),
  quiet_enabled = coalesce(quiet_enabled, false),
  quiet_start = coalesce(quiet_start, '22:00:00'::time),
  quiet_end = coalesce(quiet_end, '07:00:00'::time),
  anniversary_hour = coalesce(anniversary_hour, 9),
  timezone = coalesce(nullif(trim(timezone), ''), 'Asia/Seoul'),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now())
where
  message_enabled is null
  or image_enabled is null
  or anniversary_enabled is null
  or game_enabled is null
  or quiet_enabled is null
  or quiet_start is null
  or quiet_end is null
  or anniversary_hour is null
  or timezone is null
  or trim(timezone) = ''
  or created_at is null
  or updated_at is null;

alter table public.notification_preferences
  alter column user_id set not null,
  alter column message_enabled set default true,
  alter column message_enabled set not null,
  alter column image_enabled set default true,
  alter column image_enabled set not null,
  alter column anniversary_enabled set default true,
  alter column anniversary_enabled set not null,
  alter column game_enabled set default true,
  alter column game_enabled set not null,
  alter column quiet_enabled set default false,
  alter column quiet_enabled set not null,
  alter column quiet_start set default '22:00:00',
  alter column quiet_start set not null,
  alter column quiet_end set default '07:00:00',
  alter column quiet_end set not null,
  alter column anniversary_hour set default 9,
  alter column anniversary_hour set not null,
  alter column timezone set default 'Asia/Seoul',
  alter column timezone set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_preferences'::regclass
      and contype = 'p'
  ) then
    alter table public.notification_preferences
      add constraint notification_preferences_pkey primary key (user_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_preferences'::regclass
      and conname = 'notification_preferences_user_id_fkey'
  ) then
    alter table public.notification_preferences
      add constraint notification_preferences_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;
end $$;

alter table public.notification_preferences
  drop constraint if exists notification_preferences_anniversary_hour_check;
alter table public.notification_preferences
  add constraint notification_preferences_anniversary_hour_check
  check (anniversary_hour between 0 and 23);

insert into public.notification_preferences (user_id)
select id
from auth.users
on conflict (user_id) do nothing;

create or replace function public.seed_notification_preferences()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.seed_notification_preferences()
  from public, anon, authenticated;

drop trigger if exists auth_user_seed_notification_preferences on auth.users;
create trigger auth_user_seed_notification_preferences
after insert on auth.users
for each row execute function public.seed_notification_preferences();

create or replace function public.touch_and_validate_notification_preferences()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform now() at time zone new.timezone;
  new.updated_at = now();
  return new;
exception when invalid_parameter_value then
  raise exception 'INVALID_TIMEZONE';
end;
$$;

revoke all on function public.touch_and_validate_notification_preferences()
  from public, anon, authenticated;

drop trigger if exists notification_preferences_touch_and_validate
  on public.notification_preferences;
create trigger notification_preferences_touch_and_validate
before insert or update on public.notification_preferences
for each row execute function public.touch_and_validate_notification_preferences();

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
  dedupe_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  next_attempt_at timestamptz,
  read_at timestamptz,
  constraint notification_jobs_dedupe_key_key unique (dedupe_key),
  constraint notification_jobs_category_check
    check (category in ('anniversary', 'message', 'image', 'game')),
  constraint notification_jobs_status_check
    check (status in ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  constraint notification_jobs_attempts_nonnegative_check
    check (attempts >= 0)
);

-- Core columns are added without invented business values. If a non-empty,
-- malformed table cannot satisfy the final NOT NULL contract the transaction
-- fails and rolls back instead of silently corrupting notification history.
alter table public.notification_jobs
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists user_id uuid,
  add column if not exists couple_id uuid,
  add column if not exists category text,
  add column if not exists event_key text,
  add column if not exists event_date date,
  add column if not exists scheduled_for timestamptz,
  add column if not exists timezone text,
  add column if not exists deliver_silently boolean default false,
  add column if not exists route text,
  add column if not exists payload jsonb default '{}'::jsonb,
  add column if not exists status text default 'pending',
  add column if not exists attempts integer default 0,
  add column if not exists last_error text,
  add column if not exists sent_at timestamptz,
  add column if not exists dedupe_key text,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now(),
  add column if not exists locked_at timestamptz,
  add column if not exists locked_by text,
  add column if not exists next_attempt_at timestamptz,
  add column if not exists read_at timestamptz;

update public.notification_jobs
set
  id = coalesce(id, gen_random_uuid()),
  deliver_silently = coalesce(deliver_silently, false),
  payload = coalesce(payload, '{}'::jsonb),
  status = coalesce(status, 'pending'),
  attempts = coalesce(attempts, 0),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, now())
where
  id is null
  or deliver_silently is null
  or payload is null
  or status is null
  or attempts is null
  or created_at is null
  or updated_at is null;

alter table public.notification_jobs
  alter column id set default gen_random_uuid(),
  alter column id set not null,
  alter column user_id set not null,
  alter column category set not null,
  alter column event_key set not null,
  alter column event_date set not null,
  alter column scheduled_for set not null,
  alter column timezone set not null,
  alter column deliver_silently set default false,
  alter column deliver_silently set not null,
  alter column route set not null,
  alter column payload set default '{}'::jsonb,
  alter column payload set not null,
  alter column status set default 'pending',
  alter column status set not null,
  alter column attempts set default 0,
  alter column attempts set not null,
  alter column dedupe_key set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_jobs'::regclass
      and contype = 'p'
  ) then
    alter table public.notification_jobs
      add constraint notification_jobs_pkey primary key (id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_jobs'::regclass
      and conname = 'notification_jobs_user_id_fkey'
  ) then
    alter table public.notification_jobs
      add constraint notification_jobs_user_id_fkey
      foreign key (user_id) references auth.users(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_jobs'::regclass
      and conname = 'notification_jobs_couple_id_fkey'
  ) then
    alter table public.notification_jobs
      add constraint notification_jobs_couple_id_fkey
      foreign key (couple_id) references public.couples(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.notification_jobs'::regclass
      and conname = 'notification_jobs_dedupe_key_key'
  ) then
    alter table public.notification_jobs
      add constraint notification_jobs_dedupe_key_key unique (dedupe_key);
  end if;
end $$;

alter table public.notification_jobs
  drop constraint if exists notification_jobs_category_check,
  drop constraint if exists notification_jobs_status_check,
  drop constraint if exists notification_jobs_attempts_nonnegative_check;
alter table public.notification_jobs
  add constraint notification_jobs_category_check
    check (category in ('anniversary', 'message', 'image', 'game')),
  add constraint notification_jobs_status_check
    check (status in ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  add constraint notification_jobs_attempts_nonnegative_check
    check (attempts >= 0);

create index if not exists notification_jobs_dispatch_idx
  on public.notification_jobs(status, scheduled_for, created_at)
  where status in ('pending', 'failed');
create index if not exists notification_jobs_user_created_idx
  on public.notification_jobs(user_id, created_at desc);

create or replace function public.touch_notification_job_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.touch_notification_job_updated_at()
  from public, anon, authenticated;

drop trigger if exists notification_jobs_touch_updated_at
  on public.notification_jobs;
create trigger notification_jobs_touch_updated_at
before update on public.notification_jobs
for each row execute function public.touch_notification_job_updated_at();

create or replace function public.mark_notification_jobs_read(
  target_job_ids uuid[]
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.notification_jobs
  set read_at = coalesce(read_at, now())
  where user_id = auth.uid()
    and id = any(target_job_ids);
$$;

revoke all on function public.mark_notification_jobs_read(uuid[])
  from public, anon, authenticated;
grant execute on function public.mark_notification_jobs_read(uuid[])
  to authenticated;

alter table public.notification_preferences enable row level security;
alter table public.notification_jobs enable row level security;

drop policy if exists notification_preferences_select_own
  on public.notification_preferences;
create policy notification_preferences_select_own
  on public.notification_preferences
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists notification_preferences_insert_own
  on public.notification_preferences;
create policy notification_preferences_insert_own
  on public.notification_preferences
  for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists notification_preferences_update_own
  on public.notification_preferences;
create policy notification_preferences_update_own
  on public.notification_preferences
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists notification_jobs_select_own
  on public.notification_jobs;
create policy notification_jobs_select_own
  on public.notification_jobs
  for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.notification_preferences from public, anon;
revoke all on table public.notification_jobs from public, anon;
grant select, insert, update on table public.notification_preferences
  to authenticated;
grant select on table public.notification_jobs to authenticated;
grant all on table public.notification_preferences to service_role;
grant all on table public.notification_jobs to service_role;

alter table public.notification_preferences replica identity full;
alter table public.notification_jobs replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    raise exception 'supabase_realtime publication is required';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notification_preferences'
  ) then
    alter publication supabase_realtime
      add table public.notification_preferences;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notification_jobs'
  ) then
    alter publication supabase_realtime
      add table public.notification_jobs;
  end if;
end $$;

-- Fail the transaction if an existing object with the same name has an
-- incompatible definition. This keeps repeated runs deterministic.
do $$
declare
  invalid_columns integer;
begin
  select count(*)
  into invalid_columns
  from (
    values
      ('user_id', 'uuid', 'NO'),
      ('message_enabled', 'boolean', 'NO'),
      ('image_enabled', 'boolean', 'NO'),
      ('anniversary_enabled', 'boolean', 'NO'),
      ('game_enabled', 'boolean', 'NO'),
      ('quiet_enabled', 'boolean', 'NO'),
      ('quiet_start', 'time without time zone', 'NO'),
      ('quiet_end', 'time without time zone', 'NO'),
      ('anniversary_hour', 'smallint', 'NO'),
      ('timezone', 'text', 'NO'),
      ('created_at', 'timestamp with time zone', 'NO'),
      ('updated_at', 'timestamp with time zone', 'NO')
  ) as expected(column_name, data_type, is_nullable)
  left join information_schema.columns actual
    on actual.table_schema = 'public'
    and actual.table_name = 'notification_preferences'
    and actual.column_name = expected.column_name
  where actual.column_name is null
    or actual.data_type <> expected.data_type
    or actual.is_nullable <> expected.is_nullable;

  if invalid_columns <> 0 then
    raise exception 'notification_preferences has an unexpected column contract';
  end if;

  select count(*)
  into invalid_columns
  from (
    values
      ('id', 'uuid', 'NO'),
      ('user_id', 'uuid', 'NO'),
      ('couple_id', 'uuid', 'YES'),
      ('category', 'text', 'NO'),
      ('event_key', 'text', 'NO'),
      ('event_date', 'date', 'NO'),
      ('scheduled_for', 'timestamp with time zone', 'NO'),
      ('timezone', 'text', 'NO'),
      ('deliver_silently', 'boolean', 'NO'),
      ('route', 'text', 'NO'),
      ('payload', 'jsonb', 'NO'),
      ('status', 'text', 'NO'),
      ('attempts', 'integer', 'NO'),
      ('last_error', 'text', 'YES'),
      ('sent_at', 'timestamp with time zone', 'YES'),
      ('dedupe_key', 'text', 'NO'),
      ('created_at', 'timestamp with time zone', 'NO'),
      ('updated_at', 'timestamp with time zone', 'NO'),
      ('locked_at', 'timestamp with time zone', 'YES'),
      ('locked_by', 'text', 'YES'),
      ('next_attempt_at', 'timestamp with time zone', 'YES'),
      ('read_at', 'timestamp with time zone', 'YES')
  ) as expected(column_name, data_type, is_nullable)
  left join information_schema.columns actual
    on actual.table_schema = 'public'
    and actual.table_name = 'notification_jobs'
    and actual.column_name = expected.column_name
  where actual.column_name is null
    or actual.data_type <> expected.data_type
    or actual.is_nullable <> expected.is_nullable;

  if invalid_columns <> 0 then
    raise exception 'notification_jobs has an unexpected column contract';
  end if;
end $$;

do $$
declare
  dispatch_index_valid boolean;
  inbox_index_valid boolean;
begin
  select
    lower(indexdef) like '%(status, scheduled_for, created_at)%'
    and lower(indexdef) like '%where (status = any%pending%failed%'
  into dispatch_index_valid
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'notification_jobs'
    and indexname = 'notification_jobs_dispatch_idx';

  select lower(indexdef) like '%(user_id, created_at desc)%'
  into inbox_index_valid
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'notification_jobs'
    and indexname = 'notification_jobs_user_created_idx';

  if not coalesce(dispatch_index_valid, false) then
    raise exception 'notification_jobs_dispatch_idx has an unexpected definition';
  end if;
  if not coalesce(inbox_index_valid, false) then
    raise exception 'notification_jobs_user_created_idx has an unexpected definition';
  end if;
end $$;

do $$
begin
  if exists (
    select 1
    from auth.users users
    left join public.notification_preferences preferences
      on preferences.user_id = users.id
    where preferences.user_id is null
  ) then
    raise exception 'notification preference backfill is incomplete';
  end if;

  if not exists (
    select 1 from pg_proc
    where oid = 'public.mark_notification_jobs_read(uuid[])'::regprocedure
      and prosecdef
  ) then
    raise exception 'mark_notification_jobs_read must be security definer';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.mark_notification_jobs_read(uuid[])',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.mark_notification_jobs_read(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'mark_notification_jobs_read grants are invalid';
  end if;

  if not has_table_privilege(
    'authenticated', 'public.notification_preferences', 'SELECT'
  ) or not has_table_privilege(
    'authenticated', 'public.notification_preferences', 'INSERT'
  ) or not has_table_privilege(
    'authenticated', 'public.notification_preferences', 'UPDATE'
  ) or not has_table_privilege(
    'authenticated', 'public.notification_jobs', 'SELECT'
  ) then
    raise exception 'authenticated notification table grants are incomplete';
  end if;

  if not exists (
    select 1 from pg_class
    where oid = 'public.notification_preferences'::regclass
      and relrowsecurity
      and relreplident = 'f'
  ) or not exists (
    select 1 from pg_class
    where oid = 'public.notification_jobs'::regclass
      and relrowsecurity
      and relreplident = 'f'
  ) then
    raise exception 'notification RLS or replica identity is incomplete';
  end if;

  if (
    select count(*) from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_preferences'
      and policyname in (
        'notification_preferences_select_own',
        'notification_preferences_insert_own',
        'notification_preferences_update_own'
      )
  ) <> 3 or not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'notification_jobs'
      and policyname = 'notification_jobs_select_own'
  ) then
    raise exception 'notification RLS policies are incomplete';
  end if;

  if (
    select count(*) from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename in ('notification_preferences', 'notification_jobs')
  ) <> 2 then
    raise exception 'notification Realtime publication is incomplete';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
