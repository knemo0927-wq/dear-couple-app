-- Anniversary edit/repeat/reminder contract used by the Dear anniversary UI.
-- Safe to apply more than once to an existing `public.anniversaries` table.

alter table public.anniversaries
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists repeat_rule text not null default 'none',
  add column if not exists reminder_enabled boolean not null default true,
  add column if not exists reminder_days_before integer not null default 0,
  add column if not exists reminder_hour integer not null default 9;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.anniversaries'::regclass
      and conname = 'anniversaries_repeat_rule_check'
  ) then
    alter table public.anniversaries
      add constraint anniversaries_repeat_rule_check
      check (repeat_rule in ('none', 'yearly'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.anniversaries'::regclass
      and conname = 'anniversaries_reminder_days_before_check'
  ) then
    alter table public.anniversaries
      add constraint anniversaries_reminder_days_before_check
      check (reminder_days_before between 0 and 365);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.anniversaries'::regclass
      and conname = 'anniversaries_reminder_hour_check'
  ) then
    alter table public.anniversaries
      add constraint anniversaries_reminder_hour_check
      check (reminder_hour between 0 and 23);
  end if;
end
$$;

create index if not exists anniversaries_couple_event_date_id_idx
  on public.anniversaries (couple_id, event_date, id);

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
