begin;

-- A single aggregate query hydrates a bounded set of realtime album rows.
-- This replaces the client's former cover lookup plus one exact COUNT request
-- per album.
create or replace function public.get_memory_album_summaries(
  target_couple_id uuid,
  target_album_ids uuid[]
)
returns table (
  id uuid,
  couple_id uuid,
  name text,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  cover_photo_id uuid,
  cover_storage_path text,
  is_featured boolean,
  photo_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with requested_albums as (
    select album.*
    from public.memory_albums album
    where album.couple_id = target_couple_id
      and album.id = any(coalesce(target_album_ids, '{}'::uuid[]))
      and cardinality(coalesce(target_album_ids, '{}'::uuid[])) <= 100
      and public.current_user_has_couple(album.couple_id)
  ), photo_counts as (
    select photo.album_id, count(*)::bigint as photo_count
    from public.memory_album_photos photo
    join requested_albums album on album.id = photo.album_id
    group by photo.album_id
  )
  select
    album.id,
    album.couple_id,
    album.name,
    album.created_by,
    album.created_at,
    album.updated_at,
    album.cover_photo_id,
    cover.storage_path as cover_storage_path,
    album.is_featured,
    coalesce(counts.photo_count, 0)::bigint as photo_count
  from requested_albums album
  left join photo_counts counts on counts.album_id = album.id
  left join public.memory_album_photos cover
    on cover.id = album.cover_photo_id
   and cover.album_id = album.id
   and cover.couple_id = album.couple_id
  order by album.is_featured desc, album.updated_at desc, album.id desc;
$$;

-- Keyset pagination keeps each album request bounded and returns exact photo
-- counts and the current cover path in the same server round trip.
create or replace function public.get_memory_album_page(
  target_couple_id uuid,
  page_size integer default 30,
  cursor_is_featured boolean default null,
  cursor_updated_at timestamptz default null,
  cursor_id uuid default null
)
returns table (
  id uuid,
  couple_id uuid,
  name text,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  cover_photo_id uuid,
  cover_storage_path text,
  is_featured boolean,
  photo_count bigint,
  has_more boolean
)
language sql
stable
security definer
set search_path = public
as $$
  with candidates as (
    select album.*
    from public.memory_albums album
    where album.couple_id = target_couple_id
      and public.current_user_has_couple(album.couple_id)
      and (
        cursor_id is null
        or (
          cursor_is_featured is true
          and album.is_featured is false
        )
        or (
          album.is_featured is not distinct from cursor_is_featured
          and (
            album.updated_at < cursor_updated_at
            or (
              album.updated_at = cursor_updated_at
              and album.id < cursor_id
            )
          )
        )
      )
    order by album.is_featured desc, album.updated_at desc, album.id desc
    limit greatest(1, least(page_size, 100)) + 1
  ), numbered as (
    select
      candidate.*,
      row_number() over (
        order by candidate.is_featured desc,
                 candidate.updated_at desc,
                 candidate.id desc
      ) as row_number
    from candidates candidate
  ), visible as (
    select *
    from numbered
    where row_number <= greatest(1, least(page_size, 100))
  ), photo_counts as (
    select photo.album_id, count(*)::bigint as photo_count
    from public.memory_album_photos photo
    join visible album on album.id = photo.album_id
    group by photo.album_id
  )
  select
    album.id,
    album.couple_id,
    album.name,
    album.created_by,
    album.created_at,
    album.updated_at,
    album.cover_photo_id,
    cover.storage_path as cover_storage_path,
    album.is_featured,
    coalesce(counts.photo_count, 0)::bigint as photo_count,
    exists (
      select 1 from numbered overflow
      where overflow.row_number > greatest(1, least(page_size, 100))
    ) as has_more
  from visible album
  left join photo_counts counts on counts.album_id = album.id
  left join public.memory_album_photos cover
    on cover.id = album.cover_photo_id
   and cover.album_id = album.id
   and cover.couple_id = album.couple_id
  order by album.is_featured desc, album.updated_at desc, album.id desc;
$$;

revoke all on function public.get_memory_album_summaries(uuid, uuid[])
  from public;
revoke all on function public.get_memory_album_page(
  uuid,
  integer,
  boolean,
  timestamptz,
  uuid
) from public;
grant execute on function public.get_memory_album_summaries(uuid, uuid[])
  to authenticated;
grant execute on function public.get_memory_album_page(
  uuid,
  integer,
  boolean,
  timestamptz,
  uuid
) to authenticated;

-- A bounded realtime head cannot observe a DELETE for a photo loaded from an
-- older cursor page. Durable, couple-scoped tombstones make those deletes
-- visible without subscribing to an unbounded photo table.
create table if not exists public.memory_album_photo_deletions (
  event_id bigint generated by default as identity primary key,
  photo_id uuid not null,
  album_id uuid not null,
  couple_id uuid not null references public.couples(id) on delete cascade,
  deleted_at timestamptz not null default now()
);

create index if not exists memory_album_photo_deletions_couple_event_idx
  on public.memory_album_photo_deletions(couple_id, event_id desc);
create index if not exists memory_album_photo_deletions_photo_idx
  on public.memory_album_photo_deletions(photo_id);

alter table public.memory_album_photo_deletions enable row level security;
drop policy if exists memory_album_photo_deletions_select_couple
  on public.memory_album_photo_deletions;
create policy memory_album_photo_deletions_select_couple
  on public.memory_album_photo_deletions for select
  using (public.current_user_has_couple(couple_id));

revoke all on public.memory_album_photo_deletions from anon, authenticated;
grant select on public.memory_album_photo_deletions to authenticated;

create or replace function public.propagate_memory_album_photo_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    insert into public.memory_album_photo_deletions (
      photo_id,
      album_id,
      couple_id,
      deleted_at
    ) values (
      old.id,
      old.album_id,
      old.couple_id,
      now()
    );
    update public.memory_albums
    set updated_at = now()
    where id = old.album_id
      and couple_id = old.couple_id;
    return old;
  end if;

  if tg_op = 'UPDATE' and old.album_id is distinct from new.album_id then
    update public.memory_albums
    set updated_at = now()
    where id = old.album_id
      and couple_id = old.couple_id;
  end if;
  update public.memory_albums
  set updated_at = now()
  where id = new.album_id
    and couple_id = new.couple_id;
  return new;
end;
$$;

drop trigger if exists memory_album_photos_propagate_upsert
  on public.memory_album_photos;
create trigger memory_album_photos_propagate_upsert
after insert or update of album_id, couple_id
on public.memory_album_photos
for each row execute function public.propagate_memory_album_photo_change();

drop trigger if exists memory_album_photos_propagate_delete
  on public.memory_album_photos;
create trigger memory_album_photos_propagate_delete
after delete on public.memory_album_photos
for each row execute function public.propagate_memory_album_photo_change();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'memory_album_photo_deletions'
  ) then
    alter publication supabase_realtime
      add table public.memory_album_photo_deletions;
  end if;
end;
$$;

commit;
