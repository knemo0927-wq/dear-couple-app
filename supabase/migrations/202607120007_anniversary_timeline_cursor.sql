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
    select c.anniversary_date as started_at
    from public.couples c
    where c.id = target_couple_id
      and public.current_user_has_couple(c.id)
  ),
  hundred_days as (
    select
      'days:' || milestone::text as stable_id,
      milestone::text || '일' as title,
      (r.started_at + (milestone - 1))::date as occurrence_date,
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
    from relationship r
    cross join generate_series(100, 36500, 100) milestone
    where r.started_at is not null
      and r.started_at + (milestone - 1) >= target_today
  ),
  yearly as (
    select
      'years:' || milestone::text as stable_id,
      milestone::text || '주년' as title,
      (r.started_at + make_interval(years => milestone))::date as occurrence_date,
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
    from relationship r
    cross join generate_series(1, 100) milestone
    where r.started_at is not null
      and r.started_at + make_interval(years => milestone) >= target_today
  ),
  custom as (
    select
      'custom:' || a.id::text as stable_id,
      a.title,
      case
        when a.repeat_rule = 'yearly' then
          public.anniversary_occurrence_date(a.event_date, target_today)
        else a.event_date
      end as occurrence_date,
      'custom'::text as kind,
      a.id as custom_id,
      a.event_date as custom_event_date,
      a.created_at,
      a.updated_at,
      a.repeat_rule,
      a.reminder_enabled,
      a.reminder_days_before,
      a.reminder_hour,
      a.note,
      a.linked_album_id,
      null::integer as day_count,
      null::integer as year_count
    from public.anniversaries a
    where a.couple_id = target_couple_id
      and public.current_user_has_couple(a.couple_id)
      and (
        a.repeat_rule = 'yearly'
        or a.event_date >= target_today
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
    n.stable_id,
    n.title,
    n.occurrence_date,
    n.kind,
    n.custom_id,
    n.custom_event_date,
    n.created_at,
    n.updated_at,
    n.repeat_rule,
    n.reminder_enabled,
    n.reminder_days_before,
    n.reminder_hour,
    n.note,
    n.linked_album_id,
    n.day_count,
    n.year_count,
    n.has_more
  from numbered n
  where n.row_number <= greatest(1, least(page_size, 50))
  order by n.occurrence_date, n.stable_id;
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
