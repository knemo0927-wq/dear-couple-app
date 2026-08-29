begin;

-- Some production environments received the domestic travel tables without
-- the later photo-scope migration. Keep this repair intentionally scoped to
-- the domestic table so it is safe even when the optional world-map schema is
-- not installed yet.
do $$
begin
  if to_regclass('public.travel_city_photos') is null then
    raise exception 'public.travel_city_photos is required';
  end if;
end $$;

alter table public.travel_city_photos
  add column if not exists realtime_scope text
  generated always as (
    couple_id::text || ':' || city_id::text
  ) stored;

do $$
declare
  scope_is_valid boolean;
begin
  select
    is_generated = 'ALWAYS'
    and generation_expression ilike '%couple_id%'
    and generation_expression ilike '%city_id%'
  into scope_is_valid
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'travel_city_photos'
    and column_name = 'realtime_scope';

  if not coalesce(scope_is_valid, false) then
    raise exception 'travel_city_photos.realtime_scope has an unexpected definition';
  end if;
end $$;

create index if not exists travel_city_photos_realtime_head_idx
  on public.travel_city_photos(realtime_scope, created_at desc);

do $$
declare
  index_is_valid boolean;
begin
  select lower(indexdef) like '%(realtime_scope, created_at desc)%'
  into index_is_valid
  from pg_indexes
  where schemaname = 'public'
    and tablename = 'travel_city_photos'
    and indexname = 'travel_city_photos_realtime_head_idx';

  if not coalesce(index_is_valid, false) then
    raise exception 'travel_city_photos_realtime_head_idx has an unexpected definition';
  end if;
end $$;

-- DELETE events need the generated scope from the old row so filtered
-- subscriptions can remove the correct photo without a full refresh.
alter table public.travel_city_photos replica identity full;
alter table public.travel_city_photos enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'travel_city_photos'
  ) then
    alter publication supabase_realtime
      add table public.travel_city_photos;
  end if;
end $$;

-- Make the newly added filter column visible to PostgREST immediately.
notify pgrst, 'reload schema';

commit;
