begin;

create extension if not exists pgcrypto with schema extensions;

-- A single authorization helper keeps every couple-owned table scoped at the
-- database boundary. Client-side filters remain useful for UX, never security.
create or replace function public.current_user_has_couple(target_couple_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.couple_id = target_couple_id
  );
$$;

revoke all on function public.current_user_has_couple(uuid) from public;
grant execute on function public.current_user_has_couple(uuid) to authenticated;

-- Persisted per-user preferences replace screen-local switches.
create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  message_enabled boolean not null default true,
  image_enabled boolean not null default true,
  anniversary_enabled boolean not null default true,
  game_enabled boolean not null default true,
  quiet_enabled boolean not null default false,
  quiet_start time not null default '22:00:00',
  quiet_end time not null default '07:00:00',
  anniversary_hour smallint not null default 9
    check (anniversary_hour between 0 and 23),
  timezone text not null default 'Asia/Seoul',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.notification_preferences (user_id)
select id from auth.users
on conflict (user_id) do nothing;

create or replace function public.seed_notification_preferences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists auth_user_seed_notification_preferences on auth.users;
create trigger auth_user_seed_notification_preferences
after insert on auth.users
for each row execute function public.seed_notification_preferences();

alter table public.notification_preferences enable row level security;
drop policy if exists notification_preferences_select_own
  on public.notification_preferences;
create policy notification_preferences_select_own
  on public.notification_preferences for select
  using (user_id = auth.uid());
drop policy if exists notification_preferences_insert_own
  on public.notification_preferences;
create policy notification_preferences_insert_own
  on public.notification_preferences for insert
  with check (user_id = auth.uid());
drop policy if exists notification_preferences_update_own
  on public.notification_preferences;
create policy notification_preferences_update_own
  on public.notification_preferences for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function public.touch_and_validate_notification_preferences()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  perform now() at time zone new.timezone;
  new.updated_at = now();
  return new;
exception when invalid_parameter_value then
  raise exception 'INVALID_TIMEZONE';
end;
$$;

drop trigger if exists notification_preferences_touch_and_validate
  on public.notification_preferences;
create trigger notification_preferences_touch_and_validate
before insert or update on public.notification_preferences
for each row execute function public.touch_and_validate_notification_preferences();

-- Server-synchronized chat read cursors. The bigint cursor is monotonic and
-- avoids timestamp ambiguity when multiple messages share the same time.
create table if not exists public.conversation_reads (
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_read_message_id bigint not null references public.messages(id)
    on delete cascade,
  last_read_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (couple_id, user_id)
);

create index if not exists conversation_reads_message_idx
  on public.conversation_reads(last_read_message_id);
alter table public.conversation_reads
  drop constraint if exists conversation_reads_last_read_message_id_fkey;

create or replace function public.validate_conversation_read_cursor()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and new.last_read_message_id < old.last_read_message_id then
    raise exception 'READ_CURSOR_MUST_BE_MONOTONIC';
  end if;
  if not exists (
    select 1 from public.messages m
    where m.id = new.last_read_message_id
      and m.couple_id = new.couple_id
  ) then
    raise exception 'READ_CURSOR_MESSAGE_MISMATCH';
  end if;
  return new;
end;
$$;

drop trigger if exists conversation_reads_validate_cursor
  on public.conversation_reads;
create trigger conversation_reads_validate_cursor
before insert or update on public.conversation_reads
for each row execute function public.validate_conversation_read_cursor();
alter table public.conversation_reads enable row level security;
drop policy if exists conversation_reads_select_couple
  on public.conversation_reads;
create policy conversation_reads_select_couple
  on public.conversation_reads for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists conversation_reads_insert_own
  on public.conversation_reads;
create policy conversation_reads_insert_own
  on public.conversation_reads for insert
  with check (
    user_id = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists conversation_reads_update_own
  on public.conversation_reads;
create policy conversation_reads_update_own
  on public.conversation_reads for update
  using (
    user_id = auth.uid()
    and public.current_user_has_couple(couple_id)
  )
  with check (
    user_id = auth.uid()
    and public.current_user_has_couple(couple_id)
  );

-- Custom anniversary detail fields. Existing rows receive safe defaults and
-- the Flutter repository remains backward-compatible during rollout.
alter table public.anniversaries
  add column if not exists repeat_rule text not null default 'none',
  add column if not exists reminder_enabled boolean not null default true,
  add column if not exists reminder_days_before smallint not null default 0,
  add column if not exists reminder_hour smallint not null default 9,
  add column if not exists note text,
  add column if not exists linked_album_id uuid,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'anniversaries_repeat_rule_check'
      and conrelid = 'public.anniversaries'::regclass
  ) then
    alter table public.anniversaries
      add constraint anniversaries_repeat_rule_check
      check (repeat_rule in ('none', 'yearly'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'anniversaries_reminder_days_check'
      and conrelid = 'public.anniversaries'::regclass
  ) then
    alter table public.anniversaries
      add constraint anniversaries_reminder_days_check
      check (reminder_days_before between 0 and 365);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'anniversaries_reminder_hour_check'
      and conrelid = 'public.anniversaries'::regclass
  ) then
    alter table public.anniversaries
      add constraint anniversaries_reminder_hour_check
      check (reminder_hour between 0 and 23);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'anniversaries_linked_album_fk'
      and conrelid = 'public.anniversaries'::regclass
  ) then
    alter table public.anniversaries
      add constraint anniversaries_linked_album_fk
      foreign key (linked_album_id)
      references public.memory_albums(id)
      on delete set null;
  end if;
end $$;

create or replace function public.validate_anniversary_linked_album()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.linked_album_id is not null and not exists (
    select 1 from public.memory_albums a
    where a.id = new.linked_album_id
      and a.couple_id = new.couple_id
  ) then
    raise exception 'ANNIVERSARY_ALBUM_COUPLE_MISMATCH';
  end if;
  return new;
end;
$$;

drop trigger if exists anniversaries_validate_linked_album
  on public.anniversaries;
create trigger anniversaries_validate_linked_album
before insert or update of linked_album_id, couple_id on public.anniversaries
for each row execute function public.validate_anniversary_linked_album();

create index if not exists anniversaries_couple_event_date_id_idx
  on public.anniversaries(couple_id, event_date, id);

create or replace function public.anniversary_occurrence_date(
  event_date date,
  today date
)
returns date
language plpgsql
immutable
set search_path = public
as $$
declare
  target_year integer;
  target_month integer := extract(month from event_date)::integer;
  target_day integer := extract(day from event_date)::integer;
  last_day integer;
  candidate date;
begin
  target_year := greatest(
    extract(year from today)::integer,
    extract(year from event_date)::integer
  );
  loop
    last_day := extract(
      day from (
        make_date(target_year, target_month, 1)
        + interval '1 month - 1 day'
      )
    )::integer;
    candidate := make_date(target_year, target_month, least(target_day, last_day));
    if candidate >= today and candidate >= event_date then return candidate; end if;
    target_year := target_year + 1;
  end loop;
end;
$$;

create or replace function public.touch_anniversary_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists anniversaries_touch_updated_at
  on public.anniversaries;
create trigger anniversaries_touch_updated_at
before update on public.anniversaries
for each row execute function public.touch_anniversary_updated_at();

-- Featured/cover album state is shared couple data, never a device-local
-- preference. Normalize legacy duplicates before adding the uniqueness guard.
alter table public.memory_albums
  add column if not exists is_featured boolean not null default false,
  add column if not exists cover_photo_id uuid;

with ranked_featured as (
  select
    id,
    row_number() over (
      partition by couple_id
      order by updated_at desc nulls last, created_at desc, id
    ) as position
  from public.memory_albums
  where is_featured
)
update public.memory_albums album
set is_featured = false
from ranked_featured ranked
where album.id = ranked.id
  and ranked.position > 1;

create unique index if not exists memory_albums_one_featured_per_couple_idx
  on public.memory_albums(couple_id)
  where is_featured;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'memory_albums_cover_photo_fk'
      and conrelid = 'public.memory_albums'::regclass
  ) then
    alter table public.memory_albums
      add constraint memory_albums_cover_photo_fk
      foreign key (cover_photo_id)
      references public.memory_album_photos(id)
      on delete set null;
  end if;
end $$;

create or replace function public.validate_memory_album_cover()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.cover_photo_id is not null and not exists (
    select 1 from public.memory_album_photos p
    where p.id = new.cover_photo_id
      and p.album_id = new.id
      and p.couple_id = new.couple_id
  ) then
    raise exception 'ALBUM_COVER_PHOTO_MISMATCH';
  end if;
  return new;
end;
$$;

drop trigger if exists memory_albums_validate_cover
  on public.memory_albums;
create trigger memory_albums_validate_cover
before insert or update of cover_photo_id, couple_id on public.memory_albums
for each row execute function public.validate_memory_album_cover();

-- World-map photos use the same data shape and private storage model as the
-- domestic map.
create table if not exists public.world_country_photos (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  country_code text not null,
  storage_path text not null unique,
  caption text,
  uploaded_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'world_country_photos_country_fk'
      and conrelid = 'public.world_country_photos'::regclass
  ) then
    alter table public.world_country_photos
      add constraint world_country_photos_country_fk
      foreign key (country_code)
      references public.world_countries(code);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'world_country_photos_storage_path_check'
      and conrelid = 'public.world_country_photos'::regclass
  ) then
    alter table public.world_country_photos
      add constraint world_country_photos_storage_path_check
      check (
        storage_path like
          'couples/' || couple_id::text || '/countries/' || country_code || '/%'
      ) not valid;
  end if;
end $$;

create index if not exists world_country_photos_couple_country_idx
  on public.world_country_photos(couple_id, country_code, created_at desc);
alter table public.world_country_photos enable row level security;
drop policy if exists world_country_photos_select_couple
  on public.world_country_photos;
create policy world_country_photos_select_couple
  on public.world_country_photos for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists world_country_photos_insert_couple
  on public.world_country_photos;
create policy world_country_photos_insert_couple
  on public.world_country_photos for insert
  with check (
    uploaded_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists world_country_photos_delete_own
  on public.world_country_photos;
create policy world_country_photos_delete_own
  on public.world_country_photos for delete
  using (
    uploaded_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );

insert into storage.buckets (id, name, public, file_size_limit)
values ('world-country-photos', 'world-country-photos', false, 8388608)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit;

drop policy if exists world_country_photo_objects_select
  on storage.objects;
create policy world_country_photo_objects_select
  on storage.objects for select
  using (
    bucket_id = 'world-country-photos'
    and (storage.foldername(name))[1] = 'couples'
    and case
      when (storage.foldername(name))[2] ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then public.current_user_has_couple(
        ((storage.foldername(name))[2])::uuid
      )
      else false
    end
  );
drop policy if exists world_country_photo_objects_insert
  on storage.objects;
create policy world_country_photo_objects_insert
  on storage.objects for insert
  with check (
    bucket_id = 'world-country-photos'
    and (storage.foldername(name))[1] = 'couples'
    and name ~* '\.(jpg|jpeg|png|webp)$'
    and case
      when (storage.foldername(name))[2] ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then public.current_user_has_couple(
        ((storage.foldername(name))[2])::uuid
      )
      else false
    end
  );
drop policy if exists world_country_photo_objects_delete
  on storage.objects;
create policy world_country_photo_objects_delete
  on storage.objects for delete
  using (
    bucket_id = 'world-country-photos'
    and owner_id = auth.uid()::text
    and (storage.foldername(name))[1] = 'couples'
    and case
      when (storage.foldername(name))[2] ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then public.current_user_has_couple(
        ((storage.foldername(name))[2])::uuid
      )
      else false
    end
  );

-- Pairing codes are four unambiguous characters, expire after 24 hours, and
-- can only be guessed five times per 15-minute window.
create or replace function public.generate_pairing_code()
returns text
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  entropy bytea := gen_random_bytes(4);
  result text := '';
  position integer;
begin
  for position in 0..3 loop
    result := result || substr(
      alphabet,
      (get_byte(entropy, position) % length(alphabet)) + 1,
      1
    );
  end loop;
  return result;
end;
$$;

revoke all on function public.generate_pairing_code() from public;

alter table public.profiles
  add column if not exists pairing_code_expires_at timestamptz;
alter table public.profiles
  alter column pairing_code set default public.generate_pairing_code();

do $$
declare
  profile_row record;
  next_code text;
begin
  for profile_row in select user_id from public.profiles for update loop
    loop
      next_code := public.generate_pairing_code();
      exit when not exists (
        select 1 from public.profiles where pairing_code = next_code
      );
    end loop;
    update public.profiles
    set pairing_code = next_code,
        pairing_code_expires_at = now() + interval '24 hours'
    where user_id = profile_row.user_id;
  end loop;
end $$;

alter table public.profiles
  alter column pairing_code_expires_at set default now() + interval '24 hours';
update public.profiles
set pairing_code_expires_at = now() + interval '24 hours'
where pairing_code_expires_at is null;
alter table public.profiles
  alter column pairing_code_expires_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_pairing_code_four_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_pairing_code_four_check
      check (pairing_code ~ '^[A-HJ-NP-Z2-9]{4}$');
  end if;
end $$;

create table if not exists public.pairing_attempt_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_started_at timestamptz not null default now(),
  attempts smallint not null default 0
);
alter table public.pairing_attempt_limits enable row level security;
revoke all on public.pairing_attempt_limits from anon, authenticated;

create or replace function public.pair_with_code(target_pairing_code text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  requesting_user_id uuid := auth.uid();
  target_user_id uuid;
  target_couple_id uuid;
  created_couple_id uuid;
  current_attempts smallint;
  my_next_code text;
  partner_next_code text;
begin
  if requesting_user_id is null then raise exception 'AUTH_REQUIRED'; end if;

  insert into public.pairing_attempt_limits (
    user_id,
    window_started_at,
    attempts
  ) values (
    requesting_user_id,
    now(),
    1
  )
  on conflict (user_id) do update
  set window_started_at = case
        when pairing_attempt_limits.window_started_at < now() - interval '15 minutes'
          then now()
        else pairing_attempt_limits.window_started_at
      end,
      attempts = case
        when pairing_attempt_limits.window_started_at < now() - interval '15 minutes'
          then 1
        else pairing_attempt_limits.attempts + 1
      end
  returning attempts into current_attempts;

  if current_attempts > 5 then raise exception 'PAIRING_RATE_LIMITED'; end if;

  select couple_id into target_couple_id
  from public.profiles
  where user_id = requesting_user_id
  for update;
  if target_couple_id is not null then raise exception 'ALREADY_PAIRED'; end if;

  select user_id into target_user_id
  from public.profiles
  where pairing_code = upper(trim(target_pairing_code))
    and pairing_code_expires_at > now()
    and user_id <> requesting_user_id
  for update;
  if target_user_id is null then raise exception 'PAIRING_CODE_INVALID_OR_EXPIRED'; end if;

  select couple_id into target_couple_id
  from public.profiles
  where user_id = target_user_id;
  if target_couple_id is not null then raise exception 'PAIRING_TARGET_UNAVAILABLE'; end if;

  insert into public.couples (partner_a, partner_b)
  values (requesting_user_id, target_user_id)
  returning id into created_couple_id;

  loop
    my_next_code := public.generate_pairing_code();
    exit when not exists (
      select 1 from public.profiles where pairing_code = my_next_code
    );
  end loop;
  loop
    partner_next_code := public.generate_pairing_code();
    exit when partner_next_code <> my_next_code and not exists (
      select 1 from public.profiles where pairing_code = partner_next_code
    );
  end loop;

  update public.profiles
  set couple_id = created_couple_id,
      pairing_code = case
        when user_id = requesting_user_id then my_next_code
        else partner_next_code
      end,
      pairing_code_expires_at = now() + interval '24 hours'
  where user_id in (requesting_user_id, target_user_id);

  delete from public.pairing_attempt_limits where user_id = requesting_user_id;
  return created_couple_id;
end;
$$;

revoke all on function public.pair_with_code(text) from public;
grant execute on function public.pair_with_code(text) to authenticated;

-- Pairing code rotation is atomic and explicitly invalidates the previous code.
create or replace function public.rotate_my_pairing_code()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  next_code text;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  loop
    next_code := public.generate_pairing_code();
    exit when not exists (
      select 1 from public.profiles where pairing_code = next_code
    );
  end loop;
  update public.profiles
  set pairing_code = next_code,
      pairing_code_expires_at = now() + interval '24 hours'
  where user_id = auth.uid();
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
  return next_code;
end;
$$;

revoke all on function public.rotate_my_pairing_code() from public;
grant execute on function public.rotate_my_pairing_code() to authenticated;

-- Disconnect both members in one transaction. Shared records are retained so
-- operators can apply the product's retention policy instead of silently
-- deleting memories from a client request.
create or replace function public.disconnect_my_couple()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  target_couple_id uuid;
begin
  select couple_id into target_couple_id
  from public.profiles
  where user_id = auth.uid()
  for update;
  if target_couple_id is null then raise exception 'COUPLE_NOT_FOUND'; end if;

  update public.profiles
  set couple_id = null,
      pairing_code = public.generate_pairing_code(),
      pairing_code_expires_at = now() + interval '24 hours'
  where couple_id = target_couple_id;
end;
$$;

revoke all on function public.disconnect_my_couple() from public;
grant execute on function public.disconnect_my_couple() to authenticated;

-- This privileged function is the only supported client account-deletion
-- entry point. Deleting auth.users cascades through user-owned rows.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  requesting_user_id uuid := auth.uid();
  target_couple_id uuid;
begin
  if requesting_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  select couple_id into target_couple_id
  from public.profiles
  where user_id = requesting_user_id;

  if target_couple_id is not null then
    update public.profiles
    set couple_id = null,
        pairing_code = public.generate_pairing_code(),
        pairing_code_expires_at = now() + interval '24 hours'
    where couple_id = target_couple_id
      and user_id <> requesting_user_id;
  end if;

  delete from auth.users where id = requesting_user_id;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

-- Realtime is used only for bounded pages and incremental changes.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'conversation_reads'
  ) then
    alter publication supabase_realtime
      add table public.conversation_reads;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'world_country_photos'
  ) then
    alter publication supabase_realtime
      add table public.world_country_photos;
  end if;
end $$;

commit;
