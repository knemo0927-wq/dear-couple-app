begin;

-- Supabase stream filters accept one column. A generated scope lets the app
-- subscribe to one couple/place head without downloading every couple photo.
alter table public.travel_city_photos
  add column if not exists realtime_scope text
  generated always as (
    couple_id::text || ':' || city_id::text
  ) stored;

alter table public.world_country_photos
  add column if not exists realtime_scope text
  generated always as (
    couple_id::text || ':' || country_code
  ) stored;

create index if not exists travel_city_photos_realtime_head_idx
  on public.travel_city_photos(realtime_scope, created_at desc);
create index if not exists world_country_photos_realtime_head_idx
  on public.world_country_photos(realtime_scope, created_at desc);

-- DELETE events must retain the filtered scope so place-specific realtime
-- subscriptions can remove the correct row from their bounded head.
alter table public.travel_city_photos replica identity full;
alter table public.world_country_photos replica identity full;

alter table public.travel_city_photos enable row level security;
alter table public.world_country_photos enable row level security;

drop policy if exists travel_city_photos_delete_couple
  on public.travel_city_photos;
create policy travel_city_photos_delete_couple
  on public.travel_city_photos for delete
  using (public.current_user_has_couple(couple_id));

drop policy if exists world_country_photos_delete_own
  on public.world_country_photos;
drop policy if exists world_country_photos_delete_couple
  on public.world_country_photos;
create policy world_country_photos_delete_couple
  on public.world_country_photos for delete
  using (public.current_user_has_couple(couple_id));

-- Travel photos are relationship-owned. Either connected partner can remove
-- an object under that relationship's private storage prefix.
drop policy if exists travel_city_photo_objects_delete_couple
  on storage.objects;
create policy travel_city_photo_objects_delete_couple
  on storage.objects for delete
  using (
    bucket_id = 'travel-city-photos'
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

drop policy if exists world_country_photo_objects_delete
  on storage.objects;
create policy world_country_photo_objects_delete
  on storage.objects for delete
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

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'travel_city_photos'
  ) then
    alter publication supabase_realtime
      add table public.travel_city_photos;
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
