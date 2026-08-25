-- Memory album representative photo support.
-- Run this on Supabase before relying on "set as representative photo".

alter table public.memory_albums
add column if not exists cover_photo_id uuid null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'memory_albums_cover_photo_id_fkey'
  ) then
    alter table public.memory_albums
    add constraint memory_albums_cover_photo_id_fkey
    foreign key (cover_photo_id)
    references public.memory_album_photos(id)
    on delete set null;
  end if;
end $$;

create index if not exists memory_albums_cover_photo_id_idx
on public.memory_albums(cover_photo_id);
