-- Shared representative album support for the memory album screen.
-- Run this in Supabase SQL editor before using "대표 앨범으로 설정".

alter table public.memory_albums
add column if not exists is_featured boolean not null default false;

with ranked_albums as (
  select
    id,
    row_number() over (
      partition by couple_id
      order by is_featured desc, updated_at desc, created_at desc
    ) as rank
  from public.memory_albums
)
update public.memory_albums as album
set is_featured = ranked_albums.rank = 1
from ranked_albums
where album.id = ranked_albums.id;

create unique index if not exists memory_albums_one_featured_per_couple_idx
on public.memory_albums(couple_id)
where is_featured;
