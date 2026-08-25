begin;

-- Some cloud projects were created before the product-audit anniversary
-- foundation was deployed. Keep this migration deliberately scoped to the
-- columns and routines required by AnniversaryFullListPage.
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
    select 1 from public.memory_albums album
    where album.id = new.linked_album_id
      and album.couple_id = new.couple_id
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

create or replace function public.get_upcoming_anniversary_timeline(
  target_couple_id uuid,
  page_size integer default 15,
  cursor_date date default null,
  cursor_id text default null,
  target_today date default current_date
)
returns table (
  stable_id text,
  title text,
  occurrence_date date,
  kind text,
  custom_id uuid,
  custom_event_date date,
  created_at timestamptz,
  updated_at timestamptz,
  repeat_rule text,
  reminder_enabled boolean,
  reminder_days_before smallint,
  reminder_hour smallint,
  note text,
  linked_album_id uuid,
  day_count integer,
  year_count integer,
  has_more boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with relationship as (
    select couple.anniversary_date as started_at
    from public.couples couple
    where couple.id = target_couple_id
      and public.current_user_has_couple(couple.id)
  ),
  hundred_days as (
    select
      'days:' || milestone::text as stable_id,
      milestone::text || '일' as title,
      (relationship.started_at + (milestone - 1))::date as occurrence_date,
      'hundred_day'::text as kind,
      null::uuid as custom_id,
      null::date as custom_event_date,
      null::timestamptz as created_at,
      null::timestamptz as updated_at,
      null::text as repeat_rule,
      true as reminder_enabled,
      0::smallint as reminder_days_before,
      9::smallint as reminder_hour,
      null::text as note,
      null::uuid as linked_album_id,
      milestone::integer as day_count,
      null::integer as year_count
    from relationship
    cross join generate_series(100, 36500, 100) milestone
    where relationship.started_at is not null
      and relationship.started_at + (milestone - 1) >= target_today
  ),
  yearly as (
    select
      'years:' || milestone::text as stable_id,
      milestone::text || '주년' as title,
      (relationship.started_at + make_interval(years => milestone))::date
        as occurrence_date,
      'yearly'::text as kind,
      null::uuid as custom_id,
      null::date as custom_event_date,
      null::timestamptz as created_at,
      null::timestamptz as updated_at,
      null::text as repeat_rule,
      true as reminder_enabled,
      0::smallint as reminder_days_before,
      9::smallint as reminder_hour,
      null::text as note,
      null::uuid as linked_album_id,
      null::integer as day_count,
      milestone::integer as year_count
    from relationship
    cross join generate_series(1, 100) milestone
    where relationship.started_at is not null
      and relationship.started_at + make_interval(years => milestone) >= target_today
  ),
  custom as (
    select
      'custom:' || anniversary.id::text as stable_id,
      anniversary.title,
      case
        when anniversary.repeat_rule = 'yearly' then
          public.anniversary_occurrence_date(
            anniversary.event_date,
            target_today
          )
        else anniversary.event_date
      end as occurrence_date,
      'custom'::text as kind,
      anniversary.id as custom_id,
      anniversary.event_date as custom_event_date,
      anniversary.created_at,
      anniversary.updated_at,
      anniversary.repeat_rule,
      anniversary.reminder_enabled,
      anniversary.reminder_days_before,
      anniversary.reminder_hour,
      anniversary.note,
      anniversary.linked_album_id,
      null::integer as day_count,
      null::integer as year_count
    from public.anniversaries anniversary
    where anniversary.couple_id = target_couple_id
      and public.current_user_has_couple(anniversary.couple_id)
      and (
        anniversary.repeat_rule = 'yearly'
        or anniversary.event_date >= target_today
      )
  ),
  combined as (
    select * from hundred_days
    union all
    select * from yearly
    union all
    select * from custom
  ),
  filtered as (
    select *
    from combined
    where cursor_date is null
      or occurrence_date > cursor_date
      or (occurrence_date = cursor_date and stable_id > coalesce(cursor_id, ''))
    order by occurrence_date, stable_id
    limit greatest(1, least(page_size, 50)) + 1
  ),
  numbered as (
    select
      filtered.*,
      row_number() over (order by occurrence_date, stable_id) as row_number,
      count(*) over () > greatest(1, least(page_size, 50)) as has_more
    from filtered
  )
  select
    numbered.stable_id,
    numbered.title,
    numbered.occurrence_date,
    numbered.kind,
    numbered.custom_id,
    numbered.custom_event_date,
    numbered.created_at,
    numbered.updated_at,
    numbered.repeat_rule,
    numbered.reminder_enabled,
    numbered.reminder_days_before,
    numbered.reminder_hour,
    numbered.note,
    numbered.linked_album_id,
    numbered.day_count,
    numbered.year_count,
    numbered.has_more
  from numbered
  where numbered.row_number <= greatest(1, least(page_size, 50))
  order by numbered.occurrence_date, numbered.stable_id;
$$;

revoke all on function public.get_upcoming_anniversary_timeline(
  uuid,
  integer,
  date,
  text,
  date
) from public;
grant execute on function public.get_upcoming_anniversary_timeline(
  uuid,
  integer,
  date,
  text,
  date
) to authenticated;

notify pgrst, 'reload schema';

commit;
