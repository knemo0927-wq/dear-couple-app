begin;

-- Dear originally depended on a schema that was managed outside this
-- repository.  Keep the baseline deliberately additive so it can bootstrap a
-- clean Supabase project and can also be applied to an older hosted project
-- without dropping user data.
create extension if not exists pgcrypto with schema extensions;

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

-- Identity and relationship -------------------------------------------------

create table if not exists public.couples (
  id uuid primary key default gen_random_uuid(),
  partner_a uuid not null references auth.users(id) on delete cascade,
  partner_b uuid not null references auth.users(id) on delete cascade,
  anniversary_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint couples_distinct_partners_check check (partner_a <> partner_b)
);

create index if not exists couples_partner_a_idx on public.couples(partner_a);
create index if not exists couples_partner_b_idx on public.couples(partner_b);

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null default 'Dear',
  pairing_code text not null default public.generate_pairing_code(),
  pairing_code_expires_at timestamptz not null
    default now() + interval '24 hours',
  couple_id uuid references public.couples(id) on delete set null,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_nickname_not_blank_check check (length(trim(nickname)) > 0),
  constraint profiles_pairing_code_format_check
    check (pairing_code ~ '^[A-HJ-NP-Z2-9]{4}$')
);

-- Older deployments did not persist code expiry or profile timestamps.
alter table public.profiles
  add column if not exists pairing_code_expires_at timestamptz
    default now() + interval '24 hours',
  add column if not exists avatar_path text,
  add column if not exists created_at timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

create unique index if not exists profiles_pairing_code_key
  on public.profiles(pairing_code);
create index if not exists profiles_couple_id_idx on public.profiles(couple_id);

create or replace function public.current_user_has_couple(target_couple_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.profiles p
    where p.user_id = auth.uid()
      and p.couple_id = target_couple_id
  );
$$;

revoke all on function public.current_user_has_couple(uuid) from public;
grant execute on function public.current_user_has_couple(uuid) to authenticated;

create or replace function public.current_user_can_view_profile(
  target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() = target_user_id or exists (
    select 1
    from public.profiles me
    join public.profiles target
      on target.user_id = target_user_id
     and target.couple_id = me.couple_id
    where me.user_id = auth.uid()
      and me.couple_id is not null
  );
$$;

revoke all on function public.current_user_can_view_profile(uuid) from public;
grant execute on function public.current_user_can_view_profile(uuid)
  to authenticated;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  next_code text;
  requested_nickname text;
begin
  requested_nickname := nullif(trim(coalesce(
    new.raw_user_meta_data ->> 'nickname',
    new.raw_user_meta_data ->> 'name',
    split_part(coalesce(new.email, ''), '@', 1),
    'Dear'
  )), '');

  loop
    next_code := public.generate_pairing_code();
    exit when not exists (
      select 1 from public.profiles where pairing_code = next_code
    );
  end loop;

  insert into public.profiles (
    user_id,
    nickname,
    pairing_code,
    pairing_code_expires_at
  ) values (
    new.id,
    coalesce(requested_nickname, 'Dear'),
    next_code,
    now() + interval '24 hours'
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists auth_user_create_dear_profile on auth.users;
create trigger auth_user_create_dear_profile
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- Backfill users that existed before the baseline was installed.  The retry
-- loop makes the four-character unique code safe even with a large user set.
do $$
declare
  auth_user record;
  next_code text;
begin
  for auth_user in
    select u.id, u.email, u.raw_user_meta_data
    from auth.users u
    left join public.profiles p on p.user_id = u.id
    where p.user_id is null
  loop
    loop
      next_code := public.generate_pairing_code();
      exit when not exists (
        select 1 from public.profiles where pairing_code = next_code
      );
    end loop;
    insert into public.profiles (
      user_id,
      nickname,
      pairing_code,
      pairing_code_expires_at
    ) values (
      auth_user.id,
      coalesce(
        nullif(trim(auth_user.raw_user_meta_data ->> 'nickname'), ''),
        nullif(split_part(coalesce(auth_user.email, ''), '@', 1), ''),
        'Dear'
      ),
      next_code,
      now() + interval '24 hours'
    )
    on conflict (user_id) do nothing;
  end loop;
end;
$$;

drop trigger if exists couples_touch_updated_at on public.couples;
create trigger couples_touch_updated_at
before update on public.couples
for each row execute function public.touch_updated_at();

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

-- Chat ----------------------------------------------------------------------

create table if not exists public.messages (
  id bigint generated by default as identity primary key,
  couple_id uuid not null references public.couples(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text,
  image_path text,
  created_at timestamptz not null default now(),
  constraint messages_content_check check (
    nullif(trim(coalesce(body, '')), '') is not null
    or nullif(trim(coalesce(image_path, '')), '') is not null
  )
);

create index if not exists messages_couple_id_id_idx
  on public.messages(couple_id, id desc);
create index if not exists messages_sender_id_idx
  on public.messages(sender_id, id desc);
create unique index if not exists messages_couple_image_path_key
  on public.messages(couple_id, image_path)
  where image_path is not null;

create table if not exists public.message_reactions (
  id bigint generated by default as identity primary key,
  message_id bigint not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  emoji text not null default '❤️',
  created_at timestamptz not null default now(),
  constraint message_reactions_unique unique (message_id, user_id, emoji),
  constraint message_reactions_emoji_not_blank_check
    check (length(trim(emoji)) > 0)
);

create index if not exists message_reactions_message_id_idx
  on public.message_reactions(message_id);
create index if not exists message_reactions_user_id_idx
  on public.message_reactions(user_id);

-- Anniversaries and memory albums ------------------------------------------

create table if not exists public.anniversaries (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  title text not null,
  event_date date not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint anniversaries_title_not_blank_check
    check (length(trim(title)) > 0)
);

create index if not exists anniversaries_couple_event_date_idx
  on public.anniversaries(couple_id, event_date, id);

create table if not exists public.memory_albums (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  name text not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint memory_albums_name_not_blank_check check (length(trim(name)) > 0)
);

create index if not exists memory_albums_couple_updated_idx
  on public.memory_albums(couple_id, updated_at desc);

create table if not exists public.memory_album_photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references public.memory_albums(id) on delete cascade,
  couple_id uuid not null references public.couples(id) on delete cascade,
  storage_path text not null unique,
  uploaded_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint memory_album_photos_storage_not_blank_check
    check (length(trim(storage_path)) > 0)
);

create index if not exists memory_album_photos_album_created_idx
  on public.memory_album_photos(album_id, created_at desc, id desc);
create index if not exists memory_album_photos_couple_created_idx
  on public.memory_album_photos(couple_id, created_at desc, id desc);

create or replace function public.validate_memory_album_photo_membership()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.memory_albums album
    where album.id = new.album_id
      and album.couple_id = new.couple_id
  ) then
    raise exception 'MEMORY_ALBUM_COUPLE_MISMATCH';
  end if;
  if new.storage_path not like
      'couples/' || new.couple_id::text || '/albums/' || new.album_id::text || '/%'
  then
    raise exception 'MEMORY_ALBUM_STORAGE_PATH_MISMATCH';
  end if;
  return new;
end;
$$;

drop trigger if exists memory_album_photos_validate_membership
  on public.memory_album_photos;
create trigger memory_album_photos_validate_membership
before insert or update of album_id, couple_id, storage_path
on public.memory_album_photos
for each row execute function public.validate_memory_album_photo_membership();

drop trigger if exists memory_albums_touch_updated_at
  on public.memory_albums;
create trigger memory_albums_touch_updated_at
before update on public.memory_albums
for each row execute function public.touch_updated_at();

-- Domestic and world travel maps -------------------------------------------

create table if not exists public.travel_cities (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  region_group text not null,
  center_lat double precision not null,
  center_lng double precision not null,
  sort_order integer not null default 0
);

create table if not exists public.travel_city_visits (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  city_id uuid not null references public.travel_cities(id),
  color_hex text not null default '#E678A9',
  visited_at date,
  memo text,
  updated_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint travel_city_visits_unique unique (couple_id, city_id),
  constraint travel_city_visits_color_check
    check (color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

create index if not exists travel_city_visits_couple_updated_idx
  on public.travel_city_visits(couple_id, updated_at desc);

create table if not exists public.travel_city_photos (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  city_id uuid not null references public.travel_cities(id),
  storage_path text not null unique,
  caption text,
  uploaded_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists travel_city_photos_couple_city_created_idx
  on public.travel_city_photos(couple_id, city_id, created_at desc);

create table if not exists public.world_countries (
  code text primary key,
  iso3 text not null unique,
  name_ko text not null default '',
  name_en text not null,
  center_lat double precision not null default 0,
  center_lng double precision not null default 0,
  sort_order integer not null default 0
);

create table if not exists public.world_country_visits (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  country_code text not null references public.world_countries(code),
  color_hex text not null default '#E678A9',
  visited_at date,
  memo text,
  updated_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint world_country_visits_unique unique (couple_id, country_code),
  constraint world_country_visits_color_check
    check (color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

create index if not exists world_country_visits_couple_updated_idx
  on public.world_country_visits(couple_id, updated_at desc);

drop trigger if exists travel_city_visits_touch_updated_at
  on public.travel_city_visits;
create trigger travel_city_visits_touch_updated_at
before update on public.travel_city_visits
for each row execute function public.touch_updated_at();

drop trigger if exists world_country_visits_touch_updated_at
  on public.world_country_visits;
create trigger world_country_visits_touch_updated_at
before update on public.world_country_visits
for each row execute function public.touch_updated_at();

-- The domestic map intentionally presents 40 travel destinations.  Metro
-- rows collect their districts; SIG rows align directly with the bundled
-- municipal GeoJSON codes.
insert into public.travel_cities (
  code, name, region_group, center_lat, center_lng, sort_order
)
select seed.code, seed.name, seed.region_group, seed.center_lat, seed.center_lng,
       seed.sort_order
from (values
  ('METRO_11', '서울', '서울', 37.5665, 126.9780, 1),
  ('METRO_21', '부산', '부산', 35.1796, 129.0756, 2),
  ('METRO_22', '대구', '대구', 35.8714, 128.6014, 3),
  ('METRO_23', '인천', '인천', 37.4563, 126.7052, 4),
  ('METRO_24', '광주', '광주', 35.1595, 126.8526, 5),
  ('METRO_25', '대전', '대전', 36.3504, 127.3845, 6),
  ('METRO_26', '울산', '울산', 35.5384, 129.3114, 7),
  ('METRO_29', '세종', '세종', 36.4800, 127.2890, 8),
  ('SIG_31014', '수원', '경기', 37.2596, 127.0460, 9),
  ('SIG_31104', '고양', '경기', 37.6750, 126.7550, 10),
  ('SIG_31193', '용인', '경기', 37.3220, 127.0970, 11),
  ('SIG_31023', '성남', '경기', 37.3828, 127.1189, 12),
  ('SIG_31370', '가평', '경기', 37.805802, 127.461690, 13),
  ('SIG_32030', '강릉', '강원', 37.670101, 128.831030, 14),
  ('SIG_32060', '속초', '강원', 38.172447, 128.521058, 15),
  ('SIG_32010', '춘천', '강원', 37.902650, 127.752978, 16),
  ('SIG_32020', '원주', '강원', 37.299487, 127.953901, 17),
  ('SIG_32340', '평창', '강원', 37.529656, 128.492085, 18),
  ('SIG_32410', '양양', '강원', 38.011660, 128.576177, 19),
  ('SIG_33011', '청주', '충북', 36.654938, 127.502947, 20),
  ('SIG_33020', '충주', '충북', 36.995655, 127.909924, 21),
  ('SIG_33030', '제천', '충북', 37.066980, 128.143362, 22),
  ('SIG_34011', '천안', '충남', 36.746815, 127.219593, 23),
  ('SIG_34020', '공주', '충남', 36.468903, 127.085710, 24),
  ('SIG_34030', '보령', '충남', 36.345709, 126.575606, 25),
  ('SIG_35011', '전주', '전북', 35.794734, 127.118950, 26),
  ('SIG_35020', '군산', '전북', 35.955172, 126.742748, 27),
  ('SIG_35050', '남원', '전북', 35.427231, 127.439649, 28),
  ('SIG_36010', '목포', '전남', 34.808074, 126.414517, 29),
  ('SIG_36020', '여수', '전남', 34.636730, 127.639187, 30),
  ('SIG_36030', '순천', '전남', 34.988318, 127.407467, 31),
  ('SIG_37011', '포항', '경북', 35.960716, 129.444617, 32),
  ('SIG_37020', '경주', '경북', 35.841222, 129.231944, 33),
  ('SIG_37040', '안동', '경북', 36.575165, 128.756314, 34),
  ('SIG_38111', '창원', '경남', 35.304673, 128.645790, 35),
  ('SIG_38050', '통영', '경남', 34.826105, 128.351663, 36),
  ('SIG_38090', '거제', '경남', 34.873979, 128.629422, 37),
  ('SIG_38070', '김해', '경남', 35.271547, 128.839635, 38),
  ('SIG_39010', '제주', '제주', 33.441289, 126.576457, 39),
  ('SIG_39020', '서귀포', '제주', 33.315318, 126.548098, 40)
) as seed(code, name, region_group, center_lat, center_lng, sort_order)
on conflict (code) do update
set name = excluded.name,
    region_group = excluded.region_group,
    center_lat = excluded.center_lat,
    center_lng = excluded.center_lng,
    sort_order = excluded.sort_order;

-- Seed every code rendered by the bundled globe asset so any tappable country
-- can be persisted immediately after a clean reset.  `code` is the stable
-- join key used by the Flutter canvas and visit/photo repositories.
with country_seed as (
  select *
  from jsonb_to_recordset($world$
[
  {
    "code": "ID",
    "iso3": "IDN",
    "name_ko": "인도네시아",
    "name_en": "Indonesia",
    "center_lat": -0.124,
    "center_lng": 100.664,
    "sort_order": 0
  },
  {
    "code": "MY",
    "iso3": "MYS",
    "name_ko": "말레이시아",
    "name_en": "Malaysia",
    "center_lat": 3.9595,
    "center_lng": 114.4065,
    "sort_order": 1
  },
  {
    "code": "CL",
    "iso3": "CHL",
    "name_ko": "칠레",
    "name_en": "Chile",
    "center_lat": -35.5995,
    "center_lng": -71.723,
    "sort_order": 2
  },
  {
    "code": "BO",
    "iso3": "BOL",
    "name_ko": "볼리비아",
    "name_en": "Bolivia",
    "center_lat": -16.292,
    "center_lng": -63.5575,
    "sort_order": 3
  },
  {
    "code": "PE",
    "iso3": "PER",
    "name_ko": "페루",
    "name_en": "Peru",
    "center_lat": -9.136,
    "center_lng": -75.041,
    "sort_order": 4
  },
  {
    "code": "AR",
    "iso3": "ARG",
    "name_ko": "아르헨티나",
    "name_en": "Argentina",
    "center_lat": -37.0,
    "center_lng": -63.495,
    "sort_order": 5
  },
  {
    "code": "CY",
    "iso3": "CYP",
    "name_ko": "키프로스",
    "name_en": "Cyprus",
    "center_lat": 34.908,
    "center_lng": 32.9895,
    "sort_order": 6
  },
  {
    "code": "IN",
    "iso3": "IND",
    "name_ko": "인도",
    "name_en": "India",
    "center_lat": 22.0605,
    "center_lng": 82.6735,
    "sort_order": 7
  },
  {
    "code": "CN",
    "iso3": "CHN",
    "name_ko": "중국",
    "name_en": "China",
    "center_lat": 36.812,
    "center_lng": 104.1445,
    "sort_order": 8
  },
  {
    "code": "IL",
    "iso3": "ISR",
    "name_ko": "이스라엘",
    "name_en": "Israel",
    "center_lat": 31.4365,
    "center_lng": 35.0565,
    "sort_order": 9
  },
  {
    "code": "PS",
    "iso3": "PSE",
    "name_ko": "팔레스타인 지구",
    "name_en": "Palestine",
    "center_lat": 31.9455,
    "center_lng": 35.2235,
    "sort_order": 10
  },
  {
    "code": "LB",
    "iso3": "LBN",
    "name_ko": "레바논",
    "name_en": "Lebanon",
    "center_lat": 33.8625,
    "center_lng": 35.852,
    "sort_order": 11
  },
  {
    "code": "ET",
    "iso3": "ETH",
    "name_ko": "에티오피아",
    "name_en": "Ethiopia",
    "center_lat": 9.1265,
    "center_lng": 40.4765,
    "sort_order": 12
  },
  {
    "code": "SS",
    "iso3": "SSD",
    "name_ko": "남수단",
    "name_en": "South Sudan",
    "center_lat": 7.844,
    "center_lng": 30.029,
    "sort_order": 13
  },
  {
    "code": "SO",
    "iso3": "SOM",
    "name_ko": "소말리아",
    "name_en": "Somalia",
    "center_lat": 5.142,
    "center_lng": 46.183,
    "sort_order": 14
  },
  {
    "code": "KE",
    "iso3": "KEN",
    "name_ko": "케냐",
    "name_en": "Kenya",
    "center_lat": 0.126,
    "center_lng": 37.8105,
    "sort_order": 15
  },
  {
    "code": "MW",
    "iso3": "MWI",
    "name_ko": "말라위",
    "name_en": "Malawi",
    "center_lat": -13.3085,
    "center_lng": 34.2795,
    "sort_order": 16
  },
  {
    "code": "TZ",
    "iso3": "TZA",
    "name_ko": "탄자니아",
    "name_en": "United Republic of Tanzania",
    "center_lat": -6.363,
    "center_lng": 34.8725,
    "sort_order": 17
  },
  {
    "code": "SY",
    "iso3": "SYR",
    "name_ko": "시리아",
    "name_en": "Syria",
    "center_lat": 34.8025,
    "center_lng": 39.047,
    "sort_order": 18
  },
  {
    "code": "SR",
    "iso3": "SUR",
    "name_ko": "수리남",
    "name_en": "Suriname",
    "center_lat": 3.922,
    "center_lng": -56.014,
    "sort_order": 19
  },
  {
    "code": "GY",
    "iso3": "GUY",
    "name_ko": "가이아나",
    "name_en": "Guyana",
    "center_lat": 4.7915,
    "center_lng": -58.8445,
    "sort_order": 20
  },
  {
    "code": "KR",
    "iso3": "KOR",
    "name_ko": "대한민국",
    "name_en": "South Korea",
    "center_lat": 36.468,
    "center_lng": 127.8555,
    "sort_order": 21
  },
  {
    "code": "KP",
    "iso3": "PRK",
    "name_ko": "북한",
    "name_en": "North Korea",
    "center_lat": 40.361,
    "center_lng": 127.4905,
    "sort_order": 22
  },
  {
    "code": "MA",
    "iso3": "MAR",
    "name_ko": "모로코",
    "name_en": "Morocco",
    "center_lat": 28.679,
    "center_lng": -9.03,
    "sort_order": 23
  },
  {
    "code": "EH",
    "iso3": "ESH",
    "name_ko": "서사하라",
    "name_en": "Western Sahara",
    "center_lat": 24.2495,
    "center_lng": -12.8905,
    "sort_order": 24
  },
  {
    "code": "CR",
    "iso3": "CRI",
    "name_ko": "코스타리카",
    "name_en": "Costa Rica",
    "center_lat": 9.6065,
    "center_lng": -84.2605,
    "sort_order": 25
  },
  {
    "code": "NI",
    "iso3": "NIC",
    "name_ko": "니카라과",
    "name_en": "Nicaragua",
    "center_lat": 12.862,
    "center_lng": -85.4255,
    "sort_order": 26
  },
  {
    "code": "CG",
    "iso3": "COG",
    "name_ko": "콩고-브라자빌",
    "name_en": "Republic of the Congo",
    "center_lat": -0.6525,
    "center_lng": 14.992,
    "sort_order": 27
  },
  {
    "code": "CD",
    "iso3": "COD",
    "name_ko": "콩고-킨샤사",
    "name_en": "Democratic Republic of the Congo",
    "center_lat": -4.02,
    "center_lng": 21.726,
    "sort_order": 28
  },
  {
    "code": "BT",
    "iso3": "BTN",
    "name_ko": "부탄",
    "name_en": "Bhutan",
    "center_lat": 27.5155,
    "center_lng": 90.4125,
    "sort_order": 29
  },
  {
    "code": "UA",
    "iso3": "UKR",
    "name_ko": "우크라이나",
    "name_en": "Ukraine",
    "center_lat": 48.781,
    "center_lng": 31.145,
    "sort_order": 30
  },
  {
    "code": "BY",
    "iso3": "BLR",
    "name_ko": "벨라루스",
    "name_en": "Belarus",
    "center_lat": 53.698,
    "center_lng": 27.969,
    "sort_order": 31
  },
  {
    "code": "NA",
    "iso3": "NAM",
    "name_ko": "나미비아",
    "name_en": "Namibia",
    "center_lat": -22.9615,
    "center_lng": 18.491,
    "sort_order": 32
  },
  {
    "code": "ZA",
    "iso3": "ZAF",
    "name_ko": "남아프리카",
    "name_en": "South Africa",
    "center_lat": -28.468,
    "center_lng": 24.669,
    "sort_order": 33
  },
  {
    "code": "MF",
    "iso3": "MAF",
    "name_ko": "생마르탱",
    "name_en": "Saint Martin",
    "center_lat": 18.0775,
    "center_lng": -63.079,
    "sort_order": 34
  },
  {
    "code": "SX",
    "iso3": "SXM",
    "name_ko": "신트마르턴",
    "name_en": "Sint Maarten",
    "center_lat": 18.0405,
    "center_lng": -63.0685,
    "sort_order": 35
  },
  {
    "code": "OM",
    "iso3": "OMN",
    "name_ko": "오만",
    "name_en": "Oman",
    "center_lat": 20.8565,
    "center_lng": 55.994,
    "sort_order": 36
  },
  {
    "code": "UZ",
    "iso3": "UZB",
    "name_ko": "우즈베키스탄",
    "name_en": "Uzbekistan",
    "center_lat": 41.323,
    "center_lng": 64.4525,
    "sort_order": 37
  },
  {
    "code": "KZ",
    "iso3": "KAZ",
    "name_ko": "카자흐스탄",
    "name_en": "Kazakhstan",
    "center_lat": 47.9815,
    "center_lng": 67.1415,
    "sort_order": 38
  },
  {
    "code": "TJ",
    "iso3": "TJK",
    "name_ko": "타지키스탄",
    "name_en": "Tajikistan",
    "center_lat": 38.854,
    "center_lng": 71.256,
    "sort_order": 39
  },
  {
    "code": "LT",
    "iso3": "LTU",
    "name_ko": "리투아니아",
    "name_en": "Lithuania",
    "center_lat": 55.1575,
    "center_lng": 23.8785,
    "sort_order": 40
  },
  {
    "code": "BR",
    "iso3": "BRA",
    "name_ko": "브라질",
    "name_en": "Brazil",
    "center_lat": -13.966,
    "center_lng": -54.2985,
    "sort_order": 41
  },
  {
    "code": "UY",
    "iso3": "URY",
    "name_ko": "우루과이",
    "name_en": "Uruguay",
    "center_lat": -32.5375,
    "center_lng": -55.8105,
    "sort_order": 42
  },
  {
    "code": "MN",
    "iso3": "MNG",
    "name_ko": "몽골",
    "name_en": "Mongolia",
    "center_lat": 46.8895,
    "center_lng": 103.84,
    "sort_order": 43
  },
  {
    "code": "RU",
    "iso3": "RUS",
    "name_ko": "러시아",
    "name_en": "Russia",
    "center_lat": 59.547,
    "center_lng": 103.094,
    "sort_order": 44
  },
  {
    "code": "CZ",
    "iso3": "CZE",
    "name_ko": "체코",
    "name_en": "Czechia",
    "center_lat": 49.81,
    "center_lng": 15.4565,
    "sort_order": 45
  },
  {
    "code": "DE",
    "iso3": "DEU",
    "name_ko": "독일",
    "name_en": "Germany",
    "center_lat": 51.1005,
    "center_lng": 10.4565,
    "sort_order": 46
  },
  {
    "code": "EE",
    "iso3": "EST",
    "name_ko": "에스토니아",
    "name_en": "Estonia",
    "center_lat": 58.59,
    "center_lng": 25.7745,
    "sort_order": 47
  },
  {
    "code": "LV",
    "iso3": "LVA",
    "name_ko": "라트비아",
    "name_en": "Latvia",
    "center_lat": 56.8645,
    "center_lng": 24.581,
    "sort_order": 48
  },
  {
    "code": "SE",
    "iso3": "SWE",
    "name_ko": "스웨덴",
    "name_en": "Sweden",
    "center_lat": 62.212,
    "center_lng": 17.608,
    "sort_order": 49
  },
  {
    "code": "FI",
    "iso3": "FIN",
    "name_ko": "핀란드",
    "name_en": "Finland",
    "center_lat": 64.9485,
    "center_lng": 26.149,
    "sort_order": 50
  },
  {
    "code": "VN",
    "iso3": "VNM",
    "name_ko": "베트남",
    "name_en": "Vietnam",
    "center_lat": 15.907,
    "center_lng": 105.884,
    "sort_order": 51
  },
  {
    "code": "KH",
    "iso3": "KHM",
    "name_ko": "캄보디아",
    "name_en": "Cambodia",
    "center_lat": 12.5965,
    "center_lng": 104.927,
    "sort_order": 52
  },
  {
    "code": "LU",
    "iso3": "LUX",
    "name_ko": "룩셈부르크",
    "name_en": "Luxembourg",
    "center_lat": 49.804,
    "center_lng": 6.1125,
    "sort_order": 53
  },
  {
    "code": "AE",
    "iso3": "ARE",
    "name_ko": "아랍에미리트",
    "name_en": "United Arab Emirates",
    "center_lat": 24.3735,
    "center_lng": 53.976,
    "sort_order": 54
  },
  {
    "code": "BE",
    "iso3": "BEL",
    "name_ko": "벨기에",
    "name_en": "Belgium",
    "center_lat": 50.4955,
    "center_lng": 4.442,
    "sort_order": 55
  },
  {
    "code": "GE",
    "iso3": "GEO",
    "name_ko": "조지아",
    "name_en": "Georgia",
    "center_lat": 42.322,
    "center_lng": 43.381,
    "sort_order": 56
  },
  {
    "code": "MK",
    "iso3": "MKD",
    "name_ko": "북마케도니아",
    "name_en": "North Macedonia",
    "center_lat": 41.612,
    "center_lng": 21.7195,
    "sort_order": 57
  },
  {
    "code": "AL",
    "iso3": "ALB",
    "name_ko": "알바니아",
    "name_en": "Albania",
    "center_lat": 41.1385,
    "center_lng": 20.148,
    "sort_order": 58
  },
  {
    "code": "AZ",
    "iso3": "AZE",
    "name_ko": "아제르바이잔",
    "name_en": "Azerbaijan",
    "center_lat": 40.141,
    "center_lng": 47.6865,
    "sort_order": 59
  },
  {
    "code": "TR",
    "iso3": "TUR",
    "name_ko": "튀르키예",
    "name_en": "Turkey",
    "center_lat": 38.9475,
    "center_lng": 35.4315,
    "sort_order": 60
  },
  {
    "code": "ES",
    "iso3": "ESP",
    "name_ko": "스페인",
    "name_en": "Spain",
    "center_lat": 39.869,
    "center_lng": -3.0295,
    "sort_order": 61
  },
  {
    "code": "LA",
    "iso3": "LAO",
    "name_ko": "라오스",
    "name_en": "Laos",
    "center_lat": 18.22,
    "center_lng": 103.8955,
    "sort_order": 62
  },
  {
    "code": "KG",
    "iso3": "KGZ",
    "name_ko": "키르기스스탄",
    "name_en": "Kyrgyzstan",
    "center_lat": 41.222,
    "center_lng": 74.7505,
    "sort_order": 63
  },
  {
    "code": "AM",
    "iso3": "ARM",
    "name_ko": "아르메니아",
    "name_en": "Armenia",
    "center_lat": 40.0805,
    "center_lng": 45.015,
    "sort_order": 64
  },
  {
    "code": "DK",
    "iso3": "DNK",
    "name_ko": "덴마크",
    "name_en": "Denmark",
    "center_lat": 56.2755,
    "center_lng": 9.529,
    "sort_order": 65
  },
  {
    "code": "LY",
    "iso3": "LBY",
    "name_ko": "리비아",
    "name_en": "Libya",
    "center_lat": 26.3385,
    "center_lng": 17.2765,
    "sort_order": 66
  },
  {
    "code": "TN",
    "iso3": "TUN",
    "name_ko": "튀니지",
    "name_en": "Tunisia",
    "center_lat": 33.849,
    "center_lng": 9.502,
    "sort_order": 67
  },
  {
    "code": "RO",
    "iso3": "ROU",
    "name_ko": "루마니아",
    "name_en": "Romania",
    "center_lat": 45.9645,
    "center_lng": 25.075,
    "sort_order": 68
  },
  {
    "code": "HU",
    "iso3": "HUN",
    "name_ko": "헝가리",
    "name_en": "Hungary",
    "center_lat": 47.141,
    "center_lng": 19.504,
    "sort_order": 69
  },
  {
    "code": "SK",
    "iso3": "SVK",
    "name_ko": "슬로바키아",
    "name_en": "Slovakia",
    "center_lat": 48.6765,
    "center_lng": 19.6945,
    "sort_order": 70
  },
  {
    "code": "PL",
    "iso3": "POL",
    "name_ko": "폴란드",
    "name_en": "Poland",
    "center_lat": 51.8875,
    "center_lng": 19.1345,
    "sort_order": 71
  },
  {
    "code": "IE",
    "iso3": "IRL",
    "name_ko": "아일랜드",
    "name_en": "Ireland",
    "center_lat": 53.4405,
    "center_lng": -8.213,
    "sort_order": 72
  },
  {
    "code": "GB",
    "iso3": "GBR",
    "name_ko": "영국",
    "name_en": "United Kingdom",
    "center_lat": 54.313,
    "center_lng": -2.288,
    "sort_order": 73
  },
  {
    "code": "GR",
    "iso3": "GRC",
    "name_ko": "그리스",
    "name_en": "Greece",
    "center_lat": 39.03,
    "center_lng": 23.301,
    "sort_order": 74
  },
  {
    "code": "ZM",
    "iso3": "ZMB",
    "name_ko": "잠비아",
    "name_en": "Zambia",
    "center_lat": -13.1345,
    "center_lng": 27.7915,
    "sort_order": 75
  },
  {
    "code": "SL",
    "iso3": "SLE",
    "name_ko": "시에라리온",
    "name_en": "Sierra Leone",
    "center_lat": 8.455,
    "center_lng": -11.7845,
    "sort_order": 76
  },
  {
    "code": "GN",
    "iso3": "GIN",
    "name_ko": "기니",
    "name_en": "Guinea",
    "center_lat": 9.923,
    "center_lng": -11.3595,
    "sort_order": 77
  },
  {
    "code": "LR",
    "iso3": "LBR",
    "name_ko": "라이베리아",
    "name_en": "Liberia",
    "center_lat": 6.4465,
    "center_lng": -9.4365,
    "sort_order": 78
  },
  {
    "code": "CF",
    "iso3": "CAF",
    "name_ko": "중앙 아프리카 공화국",
    "name_en": "Central African Republic",
    "center_lat": 6.627,
    "center_lng": 20.927,
    "sort_order": 79
  },
  {
    "code": "SD",
    "iso3": "SDN",
    "name_ko": "수단",
    "name_en": "Sudan",
    "center_lat": 15.4685,
    "center_lng": 30.176,
    "sort_order": 80
  },
  {
    "code": "DJ",
    "iso3": "DJI",
    "name_ko": "지부티",
    "name_en": "Djibouti",
    "center_lat": 11.805,
    "center_lng": 42.5965,
    "sort_order": 81
  },
  {
    "code": "ER",
    "iso3": "ERI",
    "name_ko": "에리트리아",
    "name_en": "Eritrea",
    "center_lat": 15.126,
    "center_lng": 39.8215,
    "sort_order": 82
  },
  {
    "code": "AT",
    "iso3": "AUT",
    "name_ko": "오스트리아",
    "name_en": "Austria",
    "center_lat": 47.7195,
    "center_lng": 13.3335,
    "sort_order": 83
  },
  {
    "code": "IQ",
    "iso3": "IRQ",
    "name_ko": "이라크",
    "name_en": "Iraq",
    "center_lat": 33.2185,
    "center_lng": 43.7605,
    "sort_order": 84
  },
  {
    "code": "IT",
    "iso3": "ITA",
    "name_ko": "이탈리아",
    "name_en": "Italy",
    "center_lat": 42.5035,
    "center_lng": 12.567,
    "sort_order": 85
  },
  {
    "code": "CH",
    "iso3": "CHE",
    "name_ko": "스위스",
    "name_en": "Switzerland",
    "center_lat": 46.8305,
    "center_lng": 8.2195,
    "sort_order": 86
  },
  {
    "code": "IR",
    "iso3": "IRN",
    "name_ko": "이란",
    "name_en": "Iran",
    "center_lat": 32.422,
    "center_lng": 53.6515,
    "sort_order": 87
  },
  {
    "code": "NL",
    "iso3": "NLD",
    "name_ko": "네덜란드",
    "name_en": "Netherlands",
    "center_lat": 52.093,
    "center_lng": 5.3575,
    "sort_order": 88
  },
  {
    "code": "LI",
    "iso3": "LIE",
    "name_ko": "리히텐슈타인",
    "name_en": "Liechtenstein",
    "center_lat": 47.1575,
    "center_lng": 9.546,
    "sort_order": 89
  },
  {
    "code": "CI",
    "iso3": "CIV",
    "name_ko": "코트디부아르",
    "name_en": "Ivory Coast",
    "center_lat": 7.601,
    "center_lng": -5.5575,
    "sort_order": 90
  },
  {
    "code": "RS",
    "iso3": "SRB",
    "name_ko": "세르비아",
    "name_en": "Republic of Serbia",
    "center_lat": 44.194,
    "center_lng": 20.899,
    "sort_order": 91
  },
  {
    "code": "ML",
    "iso3": "MLI",
    "name_ko": "말리",
    "name_en": "Mali",
    "center_lat": 17.5745,
    "center_lng": -4.014,
    "sort_order": 92
  },
  {
    "code": "SN",
    "iso3": "SEN",
    "name_ko": "세네갈",
    "name_en": "Senegal",
    "center_lat": 14.5025,
    "center_lng": -14.417,
    "sort_order": 93
  },
  {
    "code": "NG",
    "iso3": "NGA",
    "name_ko": "나이지리아",
    "name_en": "Nigeria",
    "center_lat": 9.0225,
    "center_lng": 8.6615,
    "sort_order": 94
  },
  {
    "code": "BJ",
    "iso3": "BEN",
    "name_ko": "베냉",
    "name_en": "Benin",
    "center_lat": 9.299,
    "center_lng": 2.289,
    "sort_order": 95
  },
  {
    "code": "AO",
    "iso3": "AGO",
    "name_ko": "앙골라",
    "name_en": "Angola",
    "center_lat": -11.9305,
    "center_lng": 17.8845,
    "sort_order": 96
  },
  {
    "code": "HR",
    "iso3": "HRV",
    "name_ko": "크로아티아",
    "name_en": "Croatia",
    "center_lat": 44.7705,
    "center_lng": 16.415,
    "sort_order": 97
  },
  {
    "code": "SI",
    "iso3": "SVN",
    "name_ko": "슬로베니아",
    "name_en": "Slovenia",
    "center_lat": 46.138,
    "center_lng": 14.95,
    "sort_order": 98
  },
  {
    "code": "QA",
    "iso3": "QAT",
    "name_ko": "카타르",
    "name_en": "Qatar",
    "center_lat": 25.36,
    "center_lng": 51.1895,
    "sort_order": 99
  },
  {
    "code": "SA",
    "iso3": "SAU",
    "name_ko": "사우디아라비아",
    "name_en": "Saudi Arabia",
    "center_lat": 24.2145,
    "center_lng": 45.058,
    "sort_order": 100
  },
  {
    "code": "BW",
    "iso3": "BWA",
    "name_ko": "보츠와나",
    "name_en": "Botswana",
    "center_lat": -22.343,
    "center_lng": 24.6405,
    "sort_order": 101
  },
  {
    "code": "ZW",
    "iso3": "ZWE",
    "name_ko": "짐바브웨",
    "name_en": "Zimbabwe",
    "center_lat": -18.9865,
    "center_lng": 29.1405,
    "sort_order": 102
  },
  {
    "code": "PK",
    "iso3": "PAK",
    "name_ko": "파키스탄",
    "name_en": "Pakistan",
    "center_lat": 30.394,
    "center_lng": 69.157,
    "sort_order": 103
  },
  {
    "code": "BG",
    "iso3": "BGR",
    "name_ko": "불가리아",
    "name_en": "Bulgaria",
    "center_lat": 42.7075,
    "center_lng": 25.486,
    "sort_order": 104
  },
  {
    "code": "TH",
    "iso3": "THA",
    "name_ko": "태국",
    "name_en": "Thailand",
    "center_lat": 13.0965,
    "center_lng": 101.4605,
    "sort_order": 105
  },
  {
    "code": "SM",
    "iso3": "SMR",
    "name_ko": "산마리노",
    "name_en": "San Marino",
    "center_lat": 43.9375,
    "center_lng": 12.439,
    "sort_order": 106
  },
  {
    "code": "HT",
    "iso3": "HTI",
    "name_ko": "아이티",
    "name_en": "Haiti",
    "center_lat": 18.98,
    "center_lng": -73.092,
    "sort_order": 107
  },
  {
    "code": "DO",
    "iso3": "DOM",
    "name_ko": "도미니카 공화국",
    "name_en": "Dominican Republic",
    "center_lat": 18.7975,
    "center_lng": -70.1445,
    "sort_order": 108
  },
  {
    "code": "TD",
    "iso3": "TCD",
    "name_ko": "차드",
    "name_en": "Chad",
    "center_lat": 15.429,
    "center_lng": 18.7385,
    "sort_order": 109
  },
  {
    "code": "KW",
    "iso3": "KWT",
    "name_ko": "쿠웨이트",
    "name_en": "Kuwait",
    "center_lat": 29.316,
    "center_lng": 47.482,
    "sort_order": 110
  },
  {
    "code": "SV",
    "iso3": "SLV",
    "name_ko": "엘살바도르",
    "name_en": "El Salvador",
    "center_lat": 13.8005,
    "center_lng": -88.906,
    "sort_order": 111
  },
  {
    "code": "GT",
    "iso3": "GTM",
    "name_ko": "과테말라",
    "name_en": "Guatemala",
    "center_lat": 15.7735,
    "center_lng": -90.234,
    "sort_order": 112
  },
  {
    "code": "TL",
    "iso3": "TLS",
    "name_ko": "동티모르",
    "name_en": "East Timor",
    "center_lat": -8.8815,
    "center_lng": 126.111,
    "sort_order": 113
  },
  {
    "code": "BN",
    "iso3": "BRN",
    "name_ko": "브루나이",
    "name_en": "Brunei",
    "center_lat": 4.5375,
    "center_lng": 114.5505,
    "sort_order": 114
  },
  {
    "code": "MC",
    "iso3": "MCO",
    "name_ko": "모나코",
    "name_en": "Monaco",
    "center_lat": 43.741,
    "center_lng": 7.4015,
    "sort_order": 115
  },
  {
    "code": "DZ",
    "iso3": "DZA",
    "name_ko": "알제리",
    "name_en": "Algeria",
    "center_lat": 28.035,
    "center_lng": 1.5755,
    "sort_order": 116
  },
  {
    "code": "MZ",
    "iso3": "MOZ",
    "name_ko": "모잠비크",
    "name_en": "Mozambique",
    "center_lat": -18.6745,
    "center_lng": 35.6055,
    "sort_order": 117
  },
  {
    "code": "SZ",
    "iso3": "SWZ",
    "name_ko": "에스와티니",
    "name_en": "eSwatini",
    "center_lat": -26.5255,
    "center_lng": 31.4505,
    "sort_order": 118
  },
  {
    "code": "BI",
    "iso3": "BDI",
    "name_ko": "부룬디",
    "name_en": "Burundi",
    "center_lat": -3.3855,
    "center_lng": 29.9145,
    "sort_order": 119
  },
  {
    "code": "RW",
    "iso3": "RWA",
    "name_ko": "르완다",
    "name_en": "Rwanda",
    "center_lat": -1.9405,
    "center_lng": 29.879,
    "sort_order": 120
  },
  {
    "code": "MM",
    "iso3": "MMR",
    "name_ko": "미얀마",
    "name_en": "Myanmar",
    "center_lat": 19.3815,
    "center_lng": 96.542,
    "sort_order": 121
  },
  {
    "code": "BD",
    "iso3": "BGD",
    "name_ko": "방글라데시",
    "name_en": "Bangladesh",
    "center_lat": 23.8305,
    "center_lng": 90.32,
    "sort_order": 122
  },
  {
    "code": "AD",
    "iso3": "AND",
    "name_ko": "안도라",
    "name_en": "Andorra",
    "center_lat": 42.539,
    "center_lng": 1.5855,
    "sort_order": 123
  },
  {
    "code": "AF",
    "iso3": "AFG",
    "name_ko": "아프가니스탄",
    "name_en": "Afghanistan",
    "center_lat": 33.936,
    "center_lng": 67.6165,
    "sort_order": 124
  },
  {
    "code": "ME",
    "iso3": "MNE",
    "name_ko": "몬테네그로",
    "name_en": "Montenegro",
    "center_lat": 42.7215,
    "center_lng": 19.3955,
    "sort_order": 125
  },
  {
    "code": "BA",
    "iso3": "BIH",
    "name_ko": "보스니아 헤르체고비나",
    "name_en": "Bosnia and Herzegovina",
    "center_lat": 43.917,
    "center_lng": 17.6635,
    "sort_order": 126
  },
  {
    "code": "UG",
    "iso3": "UGA",
    "name_ko": "우간다",
    "name_en": "Uganda",
    "center_lat": 1.3315,
    "center_lng": 32.264,
    "sort_order": 127
  },
  {
    "code": "CU",
    "iso3": "CUB",
    "name_ko": "쿠바",
    "name_en": "Cuba",
    "center_lat": 21.5215,
    "center_lng": -79.5735,
    "sort_order": 128
  },
  {
    "code": "HN",
    "iso3": "HND",
    "name_ko": "온두라스",
    "name_en": "Honduras",
    "center_lat": 14.499,
    "center_lng": -86.3235,
    "sort_order": 129
  },
  {
    "code": "EC",
    "iso3": "ECU",
    "name_ko": "에콰도르",
    "name_en": "Ecuador",
    "center_lat": -1.7655,
    "center_lng": -78.1225,
    "sort_order": 130
  },
  {
    "code": "CO",
    "iso3": "COL",
    "name_ko": "콜롬비아",
    "name_en": "Colombia",
    "center_lat": 4.116,
    "center_lng": -72.9695,
    "sort_order": 131
  },
  {
    "code": "PY",
    "iso3": "PRY",
    "name_ko": "파라과이",
    "name_en": "Paraguay",
    "center_lat": -23.456,
    "center_lng": -58.456,
    "sort_order": 132
  },
  {
    "code": "PT",
    "iso3": "PRT",
    "name_ko": "포르투갈",
    "name_en": "Portugal",
    "center_lat": 39.5665,
    "center_lng": -7.8575,
    "sort_order": 133
  },
  {
    "code": "MD",
    "iso3": "MDA",
    "name_ko": "몰도바",
    "name_en": "Moldova",
    "center_lat": 46.9775,
    "center_lng": 28.3525,
    "sort_order": 134
  },
  {
    "code": "TM",
    "iso3": "TKM",
    "name_ko": "투르크메니스탄",
    "name_en": "Turkmenistan",
    "center_lat": 38.905,
    "center_lng": 59.5135,
    "sort_order": 135
  },
  {
    "code": "JO",
    "iso3": "JOR",
    "name_ko": "요르단",
    "name_en": "Jordan",
    "center_lat": 31.2175,
    "center_lng": 37.1075,
    "sort_order": 136
  },
  {
    "code": "NP",
    "iso3": "NPL",
    "name_ko": "네팔",
    "name_en": "Nepal",
    "center_lat": 28.3785,
    "center_lng": 84.1155,
    "sort_order": 137
  },
  {
    "code": "LS",
    "iso3": "LSO",
    "name_ko": "레소토",
    "name_en": "Lesotho",
    "center_lat": -29.609,
    "center_lng": 28.2105,
    "sort_order": 138
  },
  {
    "code": "CM",
    "iso3": "CMR",
    "name_ko": "카메룬",
    "name_en": "Cameroon",
    "center_lat": 7.2715,
    "center_lng": 12.34,
    "sort_order": 139
  },
  {
    "code": "GA",
    "iso3": "GAB",
    "name_ko": "가봉",
    "name_en": "Gabon",
    "center_lat": -0.738,
    "center_lng": 11.6005,
    "sort_order": 140
  },
  {
    "code": "NE",
    "iso3": "NER",
    "name_ko": "니제르",
    "name_en": "Niger",
    "center_lat": 17.597,
    "center_lng": 8.076,
    "sort_order": 141
  },
  {
    "code": "BF",
    "iso3": "BFA",
    "name_ko": "부르키나파소",
    "name_en": "Burkina Faso",
    "center_lat": 12.2775,
    "center_lng": -1.5575,
    "sort_order": 142
  },
  {
    "code": "TG",
    "iso3": "TGO",
    "name_ko": "토고",
    "name_en": "Togo",
    "center_lat": 8.6435,
    "center_lng": 0.789,
    "sort_order": 143
  },
  {
    "code": "GH",
    "iso3": "GHA",
    "name_ko": "가나",
    "name_en": "Ghana",
    "center_lat": 7.951,
    "center_lng": -1.06,
    "sort_order": 144
  },
  {
    "code": "GW",
    "iso3": "GNB",
    "name_ko": "기니비사우",
    "name_en": "Guinea-Bissau",
    "center_lat": 11.811,
    "center_lng": -15.1775,
    "sort_order": 145
  },
  {
    "code": "GI",
    "iso3": "GIB",
    "name_ko": "지브롤터",
    "name_en": "Gibraltar",
    "center_lat": 36.126,
    "center_lng": -5.3485,
    "sort_order": 146
  },
  {
    "code": "US",
    "iso3": "USA",
    "name_ko": "미국",
    "name_en": "United States of America",
    "center_lat": 37.0945,
    "center_lng": -95.779,
    "sort_order": 147
  },
  {
    "code": "CA",
    "iso3": "CAN",
    "name_ko": "캐나다",
    "name_en": "Canada",
    "center_lat": 56.851,
    "center_lng": -98.3765,
    "sort_order": 148
  },
  {
    "code": "MX",
    "iso3": "MEX",
    "name_ko": "멕시코",
    "name_en": "Mexico",
    "center_lat": 23.587,
    "center_lng": -101.9705,
    "sort_order": 149
  },
  {
    "code": "BZ",
    "iso3": "BLZ",
    "name_ko": "벨리즈",
    "name_en": "Belize",
    "center_lat": 17.186,
    "center_lng": -88.66,
    "sort_order": 150
  },
  {
    "code": "PA",
    "iso3": "PAN",
    "name_ko": "파나마",
    "name_en": "Panama",
    "center_lat": 8.4125,
    "center_lng": -80.0745,
    "sort_order": 151
  },
  {
    "code": "VE",
    "iso3": "VEN",
    "name_ko": "베네수엘라",
    "name_en": "Venezuela",
    "center_lat": 6.445,
    "center_lng": -66.6665,
    "sort_order": 152
  },
  {
    "code": "PG",
    "iso3": "PNG",
    "name_ko": "파푸아뉴기니",
    "name_en": "Papua New Guinea",
    "center_lat": -6.6375,
    "center_lng": 145.7745,
    "sort_order": 153
  },
  {
    "code": "EG",
    "iso3": "EGY",
    "name_ko": "이집트",
    "name_en": "Egypt",
    "center_lat": 26.8055,
    "center_lng": 30.804,
    "sort_order": 154
  },
  {
    "code": "YE",
    "iso3": "YEM",
    "name_ko": "예멘",
    "name_en": "Yemen",
    "center_lat": 15.803,
    "center_lng": 47.8245,
    "sort_order": 155
  },
  {
    "code": "MR",
    "iso3": "MRT",
    "name_ko": "모리타니",
    "name_en": "Mauritania",
    "center_lat": 21.0155,
    "center_lng": -11.1555,
    "sort_order": 156
  },
  {
    "code": "GQ",
    "iso3": "GNQ",
    "name_ko": "적도 기니",
    "name_en": "Equatorial Guinea",
    "center_lat": 1.6335,
    "center_lng": 10.3475,
    "sort_order": 157
  },
  {
    "code": "GM",
    "iso3": "GMB",
    "name_ko": "감비아",
    "name_en": "Gambia",
    "center_lat": 13.442,
    "center_lng": -15.3475,
    "sort_order": 158
  },
  {
    "code": "HK",
    "iso3": "HKG",
    "name_ko": "홍콩(중국 특별행정구)",
    "name_en": "Hong Kong S.A.R.",
    "center_lat": 22.4125,
    "center_lng": 114.1555,
    "sort_order": 159
  },
  {
    "code": "VA",
    "iso3": "VAT",
    "name_ko": "바티칸 시국",
    "name_en": "Vatican",
    "center_lat": 41.9035,
    "center_lng": 12.4535,
    "sort_order": 160
  },
  {
    "code": "AQ",
    "iso3": "ATA",
    "name_ko": "남극 대륙",
    "name_en": "Antarctica",
    "center_lat": -76.7015,
    "center_lng": -3.342,
    "sort_order": 161
  },
  {
    "code": "AU",
    "iso3": "AUS",
    "name_ko": "오스트레일리아",
    "name_en": "Australia",
    "center_lat": -24.8535,
    "center_lng": 133.2615,
    "sort_order": 162
  },
  {
    "code": "GL",
    "iso3": "GRL",
    "name_ko": "그린란드",
    "name_en": "Greenland",
    "center_lat": 71.838,
    "center_lng": -42.1065,
    "sort_order": 163
  },
  {
    "code": "FJ",
    "iso3": "FJI",
    "name_ko": "피지",
    "name_en": "Fiji",
    "center_lat": -17.7905,
    "center_lng": 177.9865,
    "sort_order": 164
  },
  {
    "code": "NZ",
    "iso3": "NZL",
    "name_ko": "뉴질랜드",
    "name_en": "New Zealand",
    "center_lat": -43.6145,
    "center_lng": 170.4425,
    "sort_order": 165
  },
  {
    "code": "NC",
    "iso3": "NCL",
    "name_ko": "뉴칼레도니아",
    "name_en": "New Caledonia",
    "center_lat": -21.2445,
    "center_lng": 165.51,
    "sort_order": 166
  },
  {
    "code": "MG",
    "iso3": "MDG",
    "name_ko": "마다가스카르",
    "name_en": "Madagascar",
    "center_lat": -18.761,
    "center_lng": 46.8575,
    "sort_order": 167
  },
  {
    "code": "PH",
    "iso3": "PHL",
    "name_ko": "필리핀",
    "name_en": "Philippines",
    "center_lat": 15.583,
    "center_lng": 121.937,
    "sort_order": 168
  },
  {
    "code": "LK",
    "iso3": "LKA",
    "name_ko": "스리랑카",
    "name_en": "Sri Lanka",
    "center_lat": 7.8835,
    "center_lng": 80.7915,
    "sort_order": 169
  },
  {
    "code": "CW",
    "iso3": "CUW",
    "name_ko": "퀴라소",
    "name_en": "Curaçao",
    "center_lat": 12.2165,
    "center_lng": -68.956,
    "sort_order": 170
  },
  {
    "code": "AW",
    "iso3": "ABW",
    "name_ko": "아루바",
    "name_en": "Aruba",
    "center_lat": 12.525,
    "center_lng": -69.9695,
    "sort_order": 171
  },
  {
    "code": "BS",
    "iso3": "BHS",
    "name_ko": "바하마",
    "name_en": "The Bahamas",
    "center_lat": 26.406,
    "center_lng": -77.489,
    "sort_order": 172
  },
  {
    "code": "TC",
    "iso3": "TCA",
    "name_ko": "터크스 케이커스 제도",
    "name_en": "Turks and Caicos Islands",
    "center_lat": 21.8,
    "center_lng": -71.741,
    "sort_order": 173
  },
  {
    "code": "CN-TW",
    "iso3": "TWN",
    "name_ko": "대만",
    "name_en": "Taiwan",
    "center_lat": 23.6185,
    "center_lng": 121.0285,
    "sort_order": 174
  },
  {
    "code": "JP",
    "iso3": "JPN",
    "name_ko": "일본",
    "name_en": "Japan",
    "center_lat": 37.42,
    "center_lng": 136.4865,
    "sort_order": 175
  },
  {
    "code": "PM",
    "iso3": "SPM",
    "name_ko": "생피에르 미클롱",
    "name_en": "Saint Pierre and Miquelon",
    "center_lat": 46.961,
    "center_lng": -56.3165,
    "sort_order": 176
  },
  {
    "code": "IS",
    "iso3": "ISL",
    "name_ko": "아이슬란드",
    "name_en": "Iceland",
    "center_lat": 64.9465,
    "center_lng": -19.106,
    "sort_order": 177
  },
  {
    "code": "PN",
    "iso3": "PCN",
    "name_ko": "핏케언 제도",
    "name_en": "Pitcairn Islands",
    "center_lat": -24.369,
    "center_lng": -128.32,
    "sort_order": 178
  },
  {
    "code": "PF",
    "iso3": "PYF",
    "name_ko": "프랑스령 폴리네시아",
    "name_en": "French Polynesia",
    "center_lat": -17.6815,
    "center_lng": -149.3955,
    "sort_order": 179
  },
  {
    "code": "TF",
    "iso3": "ATF",
    "name_ko": "프랑스령 남방 지역",
    "name_en": "French Southern and Antarctic Lands",
    "center_lat": -49.186,
    "center_lng": 69.6595,
    "sort_order": 180
  },
  {
    "code": "SC",
    "iso3": "SYC",
    "name_ko": "세이셸",
    "name_en": "Seychelles",
    "center_lat": -4.6825,
    "center_lng": 55.452,
    "sort_order": 181
  },
  {
    "code": "KI",
    "iso3": "KIR",
    "name_ko": "키리바시",
    "name_en": "Kiribati",
    "center_lat": 1.871,
    "center_lng": -157.378,
    "sort_order": 182
  },
  {
    "code": "MH",
    "iso3": "MHL",
    "name_ko": "마셜 제도",
    "name_en": "Marshall Islands",
    "center_lat": 7.1195,
    "center_lng": 171.215,
    "sort_order": 183
  },
  {
    "code": "TT",
    "iso3": "TTO",
    "name_ko": "트리니다드 토바고",
    "name_en": "Trinidad and Tobago",
    "center_lat": 10.4435,
    "center_lng": -61.434,
    "sort_order": 184
  },
  {
    "code": "GD",
    "iso3": "GRD",
    "name_ko": "그레나다",
    "name_en": "Grenada",
    "center_lat": 12.1215,
    "center_lng": -61.697,
    "sort_order": 185
  },
  {
    "code": "VC",
    "iso3": "VCT",
    "name_ko": "세인트빈센트그레나딘",
    "name_en": "Saint Vincent and the Grenadines",
    "center_lat": 13.257,
    "center_lng": -61.2015,
    "sort_order": 186
  },
  {
    "code": "BB",
    "iso3": "BRB",
    "name_ko": "바베이도스",
    "name_en": "Barbados",
    "center_lat": 13.198,
    "center_lng": -59.5405,
    "sort_order": 187
  },
  {
    "code": "LC",
    "iso3": "LCA",
    "name_ko": "세인트루시아",
    "name_en": "Saint Lucia",
    "center_lat": 13.9135,
    "center_lng": -60.981,
    "sort_order": 188
  },
  {
    "code": "DM",
    "iso3": "DMA",
    "name_ko": "도미니카",
    "name_en": "Dominica",
    "center_lat": 15.418,
    "center_lng": -61.369,
    "sort_order": 189
  },
  {
    "code": "UM",
    "iso3": "UMI",
    "name_ko": "미국령 해외 제도",
    "name_en": "United States Minor Outlying Islands",
    "center_lat": 19.291,
    "center_lng": 166.6355,
    "sort_order": 190
  },
  {
    "code": "MS",
    "iso3": "MSR",
    "name_ko": "몬트세라트",
    "name_en": "Montserrat",
    "center_lat": 16.747,
    "center_lng": -62.1855,
    "sort_order": 191
  },
  {
    "code": "AG",
    "iso3": "ATG",
    "name_ko": "앤티가 바부다",
    "name_en": "Antigua and Barbuda",
    "center_lat": 17.079,
    "center_lng": -61.781,
    "sort_order": 192
  },
  {
    "code": "KN",
    "iso3": "KNA",
    "name_ko": "세인트키츠 네비스",
    "name_en": "Saint Kitts and Nevis",
    "center_lat": 17.3165,
    "center_lng": -62.743,
    "sort_order": 193
  },
  {
    "code": "VI",
    "iso3": "VIR",
    "name_ko": "미국령 버진아일랜드",
    "name_en": "United States Virgin Islands",
    "center_lat": 17.738,
    "center_lng": -64.727,
    "sort_order": 194
  },
  {
    "code": "BL",
    "iso3": "BLM",
    "name_ko": "생바르텔레미",
    "name_en": "Saint Barthelemy",
    "center_lat": 17.9055,
    "center_lng": -62.8295,
    "sort_order": 195
  },
  {
    "code": "PR",
    "iso3": "PRI",
    "name_ko": "푸에르토리코",
    "name_en": "Puerto Rico",
    "center_lat": 18.223,
    "center_lng": -66.4335,
    "sort_order": 196
  },
  {
    "code": "AI",
    "iso3": "AIA",
    "name_ko": "앵귈라",
    "name_en": "Anguilla",
    "center_lat": 18.2225,
    "center_lng": -63.0705,
    "sort_order": 197
  },
  {
    "code": "VG",
    "iso3": "VGB",
    "name_ko": "영국령 버진아일랜드",
    "name_en": "British Virgin Islands",
    "center_lat": 18.4185,
    "center_lng": -64.6155,
    "sort_order": 198
  },
  {
    "code": "JM",
    "iso3": "JAM",
    "name_ko": "자메이카",
    "name_en": "Jamaica",
    "center_lat": 18.1075,
    "center_lng": -77.2865,
    "sort_order": 199
  },
  {
    "code": "KY",
    "iso3": "CYM",
    "name_ko": "케이맨 제도",
    "name_en": "Cayman Islands",
    "center_lat": 19.3295,
    "center_lng": -81.252,
    "sort_order": 200
  },
  {
    "code": "BM",
    "iso3": "BMU",
    "name_ko": "버뮤다",
    "name_en": "Bermuda",
    "center_lat": 32.3185,
    "center_lng": -64.767,
    "sort_order": 201
  },
  {
    "code": "HM",
    "iso3": "HMD",
    "name_ko": "허드 맥도널드 제도",
    "name_en": "Heard Island and McDonald Islands",
    "center_lat": -53.0775,
    "center_lng": 73.524,
    "sort_order": 202
  },
  {
    "code": "SH",
    "iso3": "SHN",
    "name_ko": "세인트헬레나",
    "name_en": "Saint Helena",
    "center_lat": -15.959,
    "center_lng": -5.72,
    "sort_order": 203
  },
  {
    "code": "MU",
    "iso3": "MUS",
    "name_ko": "모리셔스",
    "name_en": "Mauritius",
    "center_lat": -20.247,
    "center_lng": 57.5495,
    "sort_order": 204
  },
  {
    "code": "KM",
    "iso3": "COM",
    "name_ko": "코모로",
    "name_en": "Comoros",
    "center_lat": -11.647,
    "center_lng": 43.356,
    "sort_order": 205
  },
  {
    "code": "ST",
    "iso3": "STP",
    "name_ko": "상투메 프린시페",
    "name_en": "São Tomé and Principe",
    "center_lat": 0.2175,
    "center_lng": 6.6115,
    "sort_order": 206
  },
  {
    "code": "CV",
    "iso3": "CPV",
    "name_ko": "카보베르데",
    "name_en": "Cabo Verde",
    "center_lat": 15.121,
    "center_lng": -23.618,
    "sort_order": 207
  },
  {
    "code": "MT",
    "iso3": "MLT",
    "name_ko": "몰타",
    "name_en": "Malta",
    "center_lat": 35.8975,
    "center_lng": 14.4445,
    "sort_order": 208
  },
  {
    "code": "JE",
    "iso3": "JEY",
    "name_ko": "저지",
    "name_en": "Jersey",
    "center_lat": 49.219,
    "center_lng": -2.125,
    "sort_order": 209
  },
  {
    "code": "GG",
    "iso3": "GGY",
    "name_ko": "건지",
    "name_en": "Guernsey",
    "center_lat": 49.4715,
    "center_lng": -2.5875,
    "sort_order": 210
  },
  {
    "code": "IM",
    "iso3": "IMN",
    "name_ko": "맨섬",
    "name_en": "Isle of Man",
    "center_lat": 54.238,
    "center_lng": -4.551,
    "sort_order": 211
  },
  {
    "code": "AX",
    "iso3": "ALA",
    "name_ko": "올란드 제도",
    "name_en": "Aland",
    "center_lat": 60.227,
    "center_lng": 19.9535,
    "sort_order": 212
  },
  {
    "code": "FO",
    "iso3": "FRO",
    "name_ko": "페로 제도",
    "name_en": "Faroe Islands",
    "center_lat": 62.1265,
    "center_lng": -6.9675,
    "sort_order": 213
  },
  {
    "code": "IO",
    "iso3": "IOT",
    "name_ko": "영국령 인도양 지역",
    "name_en": "British Indian Ocean Territory",
    "center_lat": -7.35,
    "center_lng": 72.4215,
    "sort_order": 214
  },
  {
    "code": "SG",
    "iso3": "SGP",
    "name_ko": "싱가포르",
    "name_en": "Singapore",
    "center_lat": 1.3565,
    "center_lng": 103.8215,
    "sort_order": 215
  },
  {
    "code": "NF",
    "iso3": "NFK",
    "name_ko": "노퍽섬",
    "name_en": "Norfolk Island",
    "center_lat": -29.0385,
    "center_lng": 167.954,
    "sort_order": 216
  },
  {
    "code": "CK",
    "iso3": "COK",
    "name_ko": "쿡 제도",
    "name_en": "Cook Islands",
    "center_lat": -21.22,
    "center_lng": -159.791,
    "sort_order": 217
  },
  {
    "code": "TO",
    "iso3": "TON",
    "name_ko": "통가",
    "name_en": "Tonga",
    "center_lat": -21.1655,
    "center_lng": -175.208,
    "sort_order": 218
  },
  {
    "code": "WF",
    "iso3": "WLF",
    "name_ko": "왈리스-푸투나 제도",
    "name_en": "Wallis and Futuna",
    "center_lat": -14.276,
    "center_lng": -178.1165,
    "sort_order": 219
  },
  {
    "code": "WS",
    "iso3": "WSM",
    "name_ko": "사모아",
    "name_en": "Samoa",
    "center_lat": -13.634,
    "center_lng": -172.4795,
    "sort_order": 220
  },
  {
    "code": "SB",
    "iso3": "SLB",
    "name_ko": "솔로몬 제도",
    "name_en": "Solomon Islands",
    "center_lat": -8.053,
    "center_lng": 159.166,
    "sort_order": 221
  },
  {
    "code": "TV",
    "iso3": "TUV",
    "name_ko": "투발루",
    "name_en": "Tuvalu",
    "center_lat": -8.5015,
    "center_lng": 179.2045,
    "sort_order": 222
  },
  {
    "code": "MV",
    "iso3": "MDV",
    "name_ko": "몰디브",
    "name_en": "Maldives",
    "center_lat": 4.2025,
    "center_lng": 73.492,
    "sort_order": 223
  },
  {
    "code": "NR",
    "iso3": "NRU",
    "name_ko": "나우루",
    "name_en": "Nauru",
    "center_lat": -0.521,
    "center_lng": 166.9325,
    "sort_order": 224
  },
  {
    "code": "FM",
    "iso3": "FSM",
    "name_ko": "미크로네시아",
    "name_en": "Federated States of Micronesia",
    "center_lat": 6.8835,
    "center_lng": 158.2325,
    "sort_order": 225
  },
  {
    "code": "GS",
    "iso3": "SGS",
    "name_ko": "사우스조지아 사우스샌드위치 제도",
    "name_en": "South Georgia and the Islands",
    "center_lat": -54.435,
    "center_lng": -36.898,
    "sort_order": 226
  },
  {
    "code": "FK",
    "iso3": "FLK",
    "name_ko": "포클랜드 제도",
    "name_en": "Falkland Islands",
    "center_lat": -51.789,
    "center_lng": -58.738,
    "sort_order": 227
  },
  {
    "code": "VU",
    "iso3": "VUT",
    "name_ko": "바누아투",
    "name_en": "Vanuatu",
    "center_lat": -15.1415,
    "center_lng": 166.8845,
    "sort_order": 228
  },
  {
    "code": "NU",
    "iso3": "NIU",
    "name_ko": "니우에",
    "name_en": "Niue",
    "center_lat": -19.0535,
    "center_lng": -169.8665,
    "sort_order": 229
  },
  {
    "code": "AS",
    "iso3": "ASM",
    "name_ko": "아메리칸 사모아",
    "name_en": "American Samoa",
    "center_lat": -14.3135,
    "center_lng": -170.699,
    "sort_order": 230
  },
  {
    "code": "PW",
    "iso3": "PLW",
    "name_ko": "팔라우",
    "name_en": "Palau",
    "center_lat": 7.545,
    "center_lng": 134.573,
    "sort_order": 231
  },
  {
    "code": "GU",
    "iso3": "GUM",
    "name_ko": "괌",
    "name_en": "Guam",
    "center_lat": 13.4475,
    "center_lng": 144.788,
    "sort_order": 232
  },
  {
    "code": "MP",
    "iso3": "MNP",
    "name_ko": "북마리아나제도",
    "name_en": "Northern Mariana Islands",
    "center_lat": 15.184,
    "center_lng": 145.753,
    "sort_order": 233
  },
  {
    "code": "BH",
    "iso3": "BHR",
    "name_ko": "바레인",
    "name_en": "Bahrain",
    "center_lat": 26.0165,
    "center_lng": 50.5475,
    "sort_order": 234
  },
  {
    "code": "MO",
    "iso3": "MAC",
    "name_ko": "마카오(중국 특별행정구)",
    "name_en": "Macao S.A.R",
    "center_lat": 22.1355,
    "center_lng": 113.5595,
    "sort_order": 235
  }
]
$world$::jsonb) as country(
    code text,
    iso3 text,
    name_ko text,
    name_en text,
    center_lat double precision,
    center_lng double precision,
    sort_order integer
  )
)
insert into public.world_countries (
  code, iso3, name_ko, name_en, center_lat, center_lng, sort_order
)
select
  code, iso3, name_ko, name_en, center_lat, center_lng, sort_order
from country_seed
on conflict (code) do update
set iso3 = excluded.iso3,
    name_ko = excluded.name_ko,
    name_en = excluded.name_en,
    center_lat = excluded.center_lat,
    center_lng = excluded.center_lng,
    sort_order = excluded.sort_order;

-- Omok ----------------------------------------------------------------------

create table if not exists public.omok_sessions (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples(id) on delete cascade,
  black_user_id uuid not null references auth.users(id) on delete cascade,
  white_user_id uuid not null references auth.users(id) on delete cascade,
  current_turn_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'playing',
  winner_user_id uuid references auth.users(id) on delete set null,
  turn_expires_at timestamptz,
  rematch_of_session_id uuid references public.omok_sessions(id)
    on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint omok_sessions_distinct_players_check
    check (black_user_id <> white_user_id),
  constraint omok_sessions_status_check check (status in (
    'playing',
    'black_win',
    'white_win',
    'black_timeout_win',
    'white_timeout_win',
    'black_resign_win',
    'white_resign_win',
    'draw',
    'cancelled'
  ))
);

create index if not exists omok_sessions_couple_created_idx
  on public.omok_sessions(couple_id, created_at desc);
create unique index if not exists omok_sessions_one_rematch_idx
  on public.omok_sessions(rematch_of_session_id)
  where rematch_of_session_id is not null;

create table if not exists public.omok_invites (
  id uuid primary key default gen_random_uuid(),
  invite_code text unique,
  invite_type text not null default 'code',
  sender_user_id uuid references auth.users(id) on delete cascade,
  recipient_user_id uuid references auth.users(id) on delete cascade,
  status text not null default 'open',
  session_id uuid references public.omok_sessions(id) on delete set null,
  expires_at timestamptz not null default now() + interval '10 minutes',
  created_at timestamptz not null default now(),
  constraint omok_invites_type_check check (invite_type in ('code', 'push')),
  constraint omok_invites_status_check
    check (status in ('open', 'used', 'expired')),
  constraint omok_invites_shape_check check (
    (invite_type = 'code' and invite_code is not null)
    or (invite_type = 'push' and recipient_user_id is not null)
  )
);

create index if not exists omok_invites_recipient_created_idx
  on public.omok_invites(recipient_user_id, created_at desc);
create index if not exists omok_invites_sender_created_baseline_idx
  on public.omok_invites(sender_user_id, created_at desc);

create table if not exists public.omok_moves (
  id bigint generated by default as identity primary key,
  session_id uuid not null references public.omok_sessions(id)
    on delete cascade,
  move_no integer not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  stone text not null,
  x smallint not null,
  y smallint not null,
  created_at timestamptz not null default now(),
  constraint omok_moves_number_unique unique (session_id, move_no),
  constraint omok_moves_cell_unique unique (session_id, x, y),
  constraint omok_moves_stone_check check (stone in ('black', 'white')),
  constraint omok_moves_x_check check (x between 0 and 14),
  constraint omok_moves_y_check check (y between 0 and 14)
);

create index if not exists omok_moves_session_move_idx
  on public.omok_moves(session_id, move_no);

create table if not exists public.omok_notifications (
  id bigint generated by default as identity primary key,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid not null references public.omok_sessions(id)
    on delete cascade,
  notification_type text not null,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint omok_notifications_type_not_blank_check
    check (length(trim(notification_type)) > 0)
);

create index if not exists omok_notifications_recipient_created_idx
  on public.omok_notifications(recipient_user_id, created_at desc);

drop trigger if exists omok_sessions_touch_updated_at
  on public.omok_sessions;
create trigger omok_sessions_touch_updated_at
before update on public.omok_sessions
for each row execute function public.touch_updated_at();

-- Push registration ---------------------------------------------------------

create table if not exists public.device_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  platform text not null,
  push_token text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint device_push_tokens_user_device_unique unique (user_id, device_id),
  constraint device_push_tokens_platform_check
    check (platform in ('ios', 'android', 'macos', 'web')),
  constraint device_push_tokens_device_not_blank_check
    check (length(trim(device_id)) > 0),
  constraint device_push_tokens_token_not_blank_check
    check (length(trim(push_token)) > 0)
);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens(user_id);
create unique index if not exists device_push_tokens_push_token_key
  on public.device_push_tokens(push_token);

drop trigger if exists device_push_tokens_touch_updated_at
  on public.device_push_tokens;
create trigger device_push_tokens_touch_updated_at
before update on public.device_push_tokens
for each row execute function public.touch_updated_at();

-- Row-level authorization ---------------------------------------------------

alter table public.couples enable row level security;
alter table public.profiles enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.anniversaries enable row level security;
alter table public.memory_albums enable row level security;
alter table public.memory_album_photos enable row level security;
alter table public.travel_cities enable row level security;
alter table public.travel_city_visits enable row level security;
alter table public.travel_city_photos enable row level security;
alter table public.world_countries enable row level security;
alter table public.world_country_visits enable row level security;
alter table public.omok_sessions enable row level security;
alter table public.omok_invites enable row level security;
alter table public.omok_moves enable row level security;
alter table public.omok_notifications enable row level security;
alter table public.device_push_tokens enable row level security;

drop policy if exists couples_select_member on public.couples;
create policy couples_select_member on public.couples for select
  using (public.current_user_has_couple(id));
drop policy if exists couples_update_member on public.couples;
create policy couples_update_member on public.couples for update
  using (public.current_user_has_couple(id))
  with check (public.current_user_has_couple(id));

drop policy if exists profiles_select_self_or_partner on public.profiles;
create policy profiles_select_self_or_partner on public.profiles for select
  using (public.current_user_can_view_profile(user_id));
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists messages_select_couple on public.messages;
create policy messages_select_couple on public.messages for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists messages_insert_couple on public.messages;
create policy messages_insert_couple on public.messages for insert
  with check (
    sender_id = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists messages_delete_own on public.messages;
create policy messages_delete_own on public.messages for delete
  using (
    sender_id = auth.uid()
    and public.current_user_has_couple(couple_id)
  );

drop policy if exists message_reactions_select_couple
  on public.message_reactions;
create policy message_reactions_select_couple
  on public.message_reactions for select
  using (exists (
    select 1 from public.messages message
    where message.id = message_id
      and public.current_user_has_couple(message.couple_id)
  ));
drop policy if exists message_reactions_insert_own
  on public.message_reactions;
create policy message_reactions_insert_own
  on public.message_reactions for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.messages message
      where message.id = message_id
        and public.current_user_has_couple(message.couple_id)
    )
  );
drop policy if exists message_reactions_delete_own
  on public.message_reactions;
create policy message_reactions_delete_own
  on public.message_reactions for delete
  using (user_id = auth.uid());

drop policy if exists anniversaries_select_couple on public.anniversaries;
create policy anniversaries_select_couple on public.anniversaries for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists anniversaries_insert_couple on public.anniversaries;
create policy anniversaries_insert_couple on public.anniversaries for insert
  with check (
    created_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists anniversaries_update_couple on public.anniversaries;
create policy anniversaries_update_couple on public.anniversaries for update
  using (public.current_user_has_couple(couple_id))
  with check (public.current_user_has_couple(couple_id));
drop policy if exists anniversaries_delete_couple on public.anniversaries;
create policy anniversaries_delete_couple on public.anniversaries for delete
  using (public.current_user_has_couple(couple_id));

drop policy if exists memory_albums_select_couple on public.memory_albums;
create policy memory_albums_select_couple on public.memory_albums for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists memory_albums_insert_couple on public.memory_albums;
create policy memory_albums_insert_couple on public.memory_albums for insert
  with check (
    created_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists memory_albums_update_couple on public.memory_albums;
create policy memory_albums_update_couple on public.memory_albums for update
  using (public.current_user_has_couple(couple_id))
  with check (public.current_user_has_couple(couple_id));
drop policy if exists memory_albums_delete_couple on public.memory_albums;
create policy memory_albums_delete_couple on public.memory_albums for delete
  using (public.current_user_has_couple(couple_id));

drop policy if exists memory_album_photos_select_couple
  on public.memory_album_photos;
create policy memory_album_photos_select_couple
  on public.memory_album_photos for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists memory_album_photos_insert_couple
  on public.memory_album_photos;
create policy memory_album_photos_insert_couple
  on public.memory_album_photos for insert
  with check (
    uploaded_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists memory_album_photos_update_couple
  on public.memory_album_photos;
create policy memory_album_photos_update_couple
  on public.memory_album_photos for update
  using (public.current_user_has_couple(couple_id))
  with check (public.current_user_has_couple(couple_id));
drop policy if exists memory_album_photos_delete_couple
  on public.memory_album_photos;
create policy memory_album_photos_delete_couple
  on public.memory_album_photos for delete
  using (public.current_user_has_couple(couple_id));

drop policy if exists travel_cities_select_authenticated
  on public.travel_cities;
create policy travel_cities_select_authenticated
  on public.travel_cities for select to authenticated using (true);
drop policy if exists world_countries_select_authenticated
  on public.world_countries;
create policy world_countries_select_authenticated
  on public.world_countries for select to authenticated using (true);

drop policy if exists travel_city_visits_select_couple
  on public.travel_city_visits;
create policy travel_city_visits_select_couple
  on public.travel_city_visits for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists travel_city_visits_insert_couple
  on public.travel_city_visits;
create policy travel_city_visits_insert_couple
  on public.travel_city_visits for insert
  with check (
    updated_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists travel_city_visits_update_couple
  on public.travel_city_visits;
create policy travel_city_visits_update_couple
  on public.travel_city_visits for update
  using (public.current_user_has_couple(couple_id))
  with check (
    updated_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists travel_city_visits_delete_couple
  on public.travel_city_visits;
create policy travel_city_visits_delete_couple
  on public.travel_city_visits for delete
  using (public.current_user_has_couple(couple_id));

drop policy if exists travel_city_photos_select_couple
  on public.travel_city_photos;
create policy travel_city_photos_select_couple
  on public.travel_city_photos for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists travel_city_photos_insert_couple
  on public.travel_city_photos;
create policy travel_city_photos_insert_couple
  on public.travel_city_photos for insert
  with check (
    uploaded_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists travel_city_photos_delete_couple
  on public.travel_city_photos;
create policy travel_city_photos_delete_couple
  on public.travel_city_photos for delete
  using (public.current_user_has_couple(couple_id));

drop policy if exists world_country_visits_select_couple
  on public.world_country_visits;
create policy world_country_visits_select_couple
  on public.world_country_visits for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists world_country_visits_insert_couple
  on public.world_country_visits;
create policy world_country_visits_insert_couple
  on public.world_country_visits for insert
  with check (
    updated_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists world_country_visits_update_couple
  on public.world_country_visits;
create policy world_country_visits_update_couple
  on public.world_country_visits for update
  using (public.current_user_has_couple(couple_id))
  with check (
    updated_by = auth.uid()
    and public.current_user_has_couple(couple_id)
  );
drop policy if exists world_country_visits_delete_couple
  on public.world_country_visits;
create policy world_country_visits_delete_couple
  on public.world_country_visits for delete
  using (public.current_user_has_couple(couple_id));

drop policy if exists omok_sessions_select_couple on public.omok_sessions;
create policy omok_sessions_select_couple on public.omok_sessions for select
  using (public.current_user_has_couple(couple_id));
drop policy if exists omok_invites_select_participant on public.omok_invites;
create policy omok_invites_select_participant on public.omok_invites for select
  using (
    sender_user_id = auth.uid()
    or recipient_user_id = auth.uid()
  );
drop policy if exists omok_moves_select_couple on public.omok_moves;
create policy omok_moves_select_couple on public.omok_moves for select
  using (exists (
    select 1 from public.omok_sessions session
    where session.id = session_id
      and public.current_user_has_couple(session.couple_id)
  ));
drop policy if exists omok_notifications_select_recipient
  on public.omok_notifications;
create policy omok_notifications_select_recipient
  on public.omok_notifications for select
  using (recipient_user_id = auth.uid());
drop policy if exists omok_notifications_update_recipient
  on public.omok_notifications;
create policy omok_notifications_update_recipient
  on public.omok_notifications for update
  using (recipient_user_id = auth.uid())
  with check (recipient_user_id = auth.uid());

drop policy if exists device_push_tokens_select_own
  on public.device_push_tokens;
create policy device_push_tokens_select_own
  on public.device_push_tokens for select using (user_id = auth.uid());
drop policy if exists device_push_tokens_insert_own
  on public.device_push_tokens;
create policy device_push_tokens_insert_own
  on public.device_push_tokens for insert with check (user_id = auth.uid());
drop policy if exists device_push_tokens_update_own
  on public.device_push_tokens;
create policy device_push_tokens_update_own
  on public.device_push_tokens for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists device_push_tokens_delete_own
  on public.device_push_tokens;
create policy device_push_tokens_delete_own
  on public.device_push_tokens for delete using (user_id = auth.uid());

-- Pairing and profile RPCs ---------------------------------------------------

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
    user_id, window_started_at, attempts
  ) values (requesting_user_id, now(), 1)
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
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
  if target_couple_id is not null then raise exception 'ALREADY_PAIRED'; end if;

  select user_id into target_user_id
  from public.profiles
  where pairing_code = upper(trim(target_pairing_code))
    and pairing_code_expires_at > now()
    and user_id <> requesting_user_id
  for update;
  if target_user_id is null then
    raise exception 'PAIRING_CODE_INVALID_OR_EXPIRED';
  end if;

  select couple_id into target_couple_id
  from public.profiles where user_id = target_user_id;
  if target_couple_id is not null then
    raise exception 'PAIRING_TARGET_UNAVAILABLE';
  end if;

  insert into public.couples(partner_a, partner_b)
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

  delete from public.pairing_attempt_limits
  where user_id = requesting_user_id;
  return created_couple_id;
end;
$$;

create or replace function public.rotate_my_pairing_code()
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  next_code text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
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

create or replace function public.disconnect_my_couple()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  target_couple_id uuid;
  profile_row record;
  next_code text;
begin
  select couple_id into target_couple_id
  from public.profiles
  where user_id = auth.uid()
  for update;
  if target_couple_id is null then raise exception 'COUPLE_NOT_FOUND'; end if;

  for profile_row in
    select user_id from public.profiles
    where couple_id = target_couple_id
    for update
  loop
    loop
      next_code := public.generate_pairing_code();
      exit when not exists (
        select 1 from public.profiles where pairing_code = next_code
      );
    end loop;
    update public.profiles
    set couple_id = null,
        pairing_code = next_code,
        pairing_code_expires_at = now() + interval '24 hours'
    where user_id = profile_row.user_id;
  end loop;
end;
$$;

create or replace function public.get_profile_stats(
  target_couple_id uuid,
  target_user_id uuid
)
returns table (
  consecutive_days integer,
  sent_photos bigint,
  received_likes bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with activity_days as (
    select distinct (m.created_at at time zone 'Asia/Seoul')::date as day
    from public.messages m
    where m.couple_id = target_couple_id
      and m.sender_id = target_user_id
    union
    select distinct (p.created_at at time zone 'Asia/Seoul')::date
    from public.memory_album_photos p
    where p.couple_id = target_couple_id
      and p.uploaded_by = target_user_id
  ), ranked_days as (
    select day, row_number() over (order by day desc)::integer as position
    from activity_days
    where day <= current_date
  ), streak as (
    select count(*)::integer as value
    from ranked_days
    where day = (
      select max(day) from activity_days where day <= current_date
    ) - (position - 1)
  )
  select
    case
      when public.current_user_has_couple(target_couple_id)
        then coalesce((select value from streak), 0)
      else 0
    end,
    case
      when public.current_user_has_couple(target_couple_id) then (
        select count(*)
        from public.messages m
        where m.couple_id = target_couple_id
          and m.sender_id = target_user_id
          and m.image_path is not null
      ) + (
        select count(*)
        from public.memory_album_photos p
        where p.couple_id = target_couple_id
          and p.uploaded_by = target_user_id
      )
      else 0
    end,
    case
      when public.current_user_has_couple(target_couple_id) then (
        select count(*)
        from public.message_reactions reaction
        join public.messages message on message.id = reaction.message_id
        where message.couple_id = target_couple_id
          and message.sender_id = target_user_id
          and reaction.user_id <> target_user_id
      )
      else 0
    end;
$$;

revoke all on function public.pair_with_code(text) from public;
revoke all on function public.rotate_my_pairing_code() from public;
revoke all on function public.disconnect_my_couple() from public;
revoke all on function public.get_profile_stats(uuid, uuid) from public;
grant execute on function public.pair_with_code(text) to authenticated;
grant execute on function public.rotate_my_pairing_code() to authenticated;
grant execute on function public.disconnect_my_couple() to authenticated;
grant execute on function public.get_profile_stats(uuid, uuid) to authenticated;

-- Omok RPCs -----------------------------------------------------------------

create or replace function public.generate_omok_invite_code()
returns text
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  entropy bytea := gen_random_bytes(6);
  result text := '';
  position integer;
begin
  for position in 0..5 loop
    result := result || substr(
      alphabet,
      (get_byte(entropy, position) % length(alphabet)) + 1,
      1
    );
  end loop;
  return result;
end;
$$;

create or replace function public.create_omok_session_internal(
  target_couple_id uuid,
  target_black_user_id uuid,
  target_white_user_id uuid,
  target_rematch_of uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  created_session_id uuid;
begin
  if target_black_user_id = target_white_user_id then
    raise exception 'OMOK_PLAYERS_MUST_DIFFER';
  end if;
  if not exists (
    select 1 from public.profiles
    where couple_id = target_couple_id
      and user_id = target_black_user_id
  ) or not exists (
    select 1 from public.profiles
    where couple_id = target_couple_id
      and user_id = target_white_user_id
  ) then
    raise exception 'OMOK_PLAYERS_NOT_IN_COUPLE';
  end if;

  insert into public.omok_sessions (
    couple_id,
    black_user_id,
    white_user_id,
    current_turn_user_id,
    status,
    turn_expires_at,
    rematch_of_session_id,
    created_by
  ) values (
    target_couple_id,
    target_black_user_id,
    target_white_user_id,
    target_black_user_id,
    'playing',
    now() + interval '30 seconds',
    target_rematch_of,
    auth.uid()
  )
  returning id into created_session_id;
  return created_session_id;
end;
$$;

create or replace function public.create_omok_invite()
returns table (invite_id uuid, invite_code text, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  target_couple_id uuid;
  next_code text;
  created_invite public.omok_invites%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select couple_id into target_couple_id
  from public.profiles where user_id = auth.uid();
  if target_couple_id is null then raise exception 'COUPLE_NOT_FOUND'; end if;

  update public.omok_invites
  set status = 'expired'
  where sender_user_id = auth.uid()
    and invite_type = 'code'
    and status = 'open';

  loop
    next_code := public.generate_omok_invite_code();
    exit when not exists (
      select 1 from public.omok_invites
      where invite_code = next_code and status = 'open'
    );
  end loop;

  insert into public.omok_invites (
    invite_code, invite_type, sender_user_id, expires_at
  ) values (
    next_code, 'code', auth.uid(), now() + interval '10 minutes'
  ) returning * into created_invite;

  return query select created_invite.id, created_invite.invite_code,
                      created_invite.expires_at;
end;
$$;

create or replace function public.create_omok_push_invite()
returns table (
  invite_id uuid,
  recipient_user_id uuid,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_couple_id uuid;
  target_recipient_id uuid;
  created_invite public.omok_invites%rowtype;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select couple_id into target_couple_id
  from public.profiles where user_id = auth.uid();
  if target_couple_id is null then raise exception 'COUPLE_NOT_FOUND'; end if;

  select user_id into target_recipient_id
  from public.profiles
  where couple_id = target_couple_id
    and user_id <> auth.uid()
  limit 1;
  if target_recipient_id is null then raise exception 'PARTNER_NOT_FOUND'; end if;

  update public.omok_invites
  set status = 'expired'
  where sender_user_id = auth.uid()
    and invite_type = 'push'
    and status = 'open';

  insert into public.omok_invites (
    invite_type,
    sender_user_id,
    recipient_user_id,
    expires_at
  ) values (
    'push',
    auth.uid(),
    target_recipient_id,
    now() + interval '10 minutes'
  ) returning * into created_invite;

  return query select created_invite.id, created_invite.recipient_user_id,
                      created_invite.expires_at;
end;
$$;

create or replace function public.join_omok_with_invite_code(
  target_invite_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_invite public.omok_invites%rowtype;
  joining_couple_id uuid;
  sender_couple_id uuid;
  created_session_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into target_invite
  from public.omok_invites
  where invite_code = upper(trim(target_invite_code))
  for update;
  if not found then raise exception 'OMOK_INVITE_NOT_FOUND'; end if;
  if target_invite.status <> 'open' then
    raise exception 'OMOK_INVITE_NOT_OPEN';
  end if;
  if target_invite.expires_at <= now() then
    update public.omok_invites set status = 'expired'
    where id = target_invite.id;
    raise exception 'OMOK_INVITE_EXPIRED';
  end if;
  if target_invite.sender_user_id = auth.uid() then
    raise exception 'OMOK_SELF_JOIN_NOT_ALLOWED';
  end if;

  select couple_id into joining_couple_id
  from public.profiles where user_id = auth.uid();
  select couple_id into sender_couple_id
  from public.profiles where user_id = target_invite.sender_user_id;
  if joining_couple_id is null or joining_couple_id is distinct from sender_couple_id then
    raise exception 'OMOK_INVITE_COUPLE_MISMATCH';
  end if;

  created_session_id := public.create_omok_session_internal(
    joining_couple_id,
    target_invite.sender_user_id,
    auth.uid(),
    null
  );
  update public.omok_invites
  set status = 'used',
      recipient_user_id = auth.uid(),
      session_id = created_session_id
  where id = target_invite.id;
  return created_session_id;
end;
$$;

create or replace function public.accept_omok_push_invite(
  target_invite_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_invite public.omok_invites%rowtype;
  target_couple_id uuid;
  sender_couple_id uuid;
  created_session_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into target_invite
  from public.omok_invites where id = target_invite_id
  for update;
  if not found then raise exception 'OMOK_INVITE_NOT_FOUND'; end if;
  if target_invite.invite_type <> 'push'
     or target_invite.recipient_user_id is distinct from auth.uid() then
    raise exception 'OMOK_INVITE_FORBIDDEN';
  end if;
  if target_invite.status = 'used' and target_invite.session_id is not null then
    return target_invite.session_id;
  end if;
  if target_invite.status <> 'open' then
    raise exception 'OMOK_INVITE_NOT_OPEN';
  end if;
  if target_invite.expires_at <= now() then
    update public.omok_invites set status = 'expired'
    where id = target_invite.id;
    raise exception 'OMOK_INVITE_EXPIRED';
  end if;

  select couple_id into target_couple_id
  from public.profiles where user_id = auth.uid();
  select couple_id into sender_couple_id
  from public.profiles where user_id = target_invite.sender_user_id;
  if target_couple_id is null
     or target_couple_id is distinct from sender_couple_id then
    raise exception 'OMOK_INVITE_COUPLE_MISMATCH';
  end if;

  created_session_id := public.create_omok_session_internal(
    target_couple_id,
    target_invite.sender_user_id,
    auth.uid(),
    null
  );
  update public.omok_invites
  set status = 'used', session_id = created_session_id
  where id = target_invite.id;
  return created_session_id;
end;
$$;

create or replace function public.place_omok_move(
  target_session_id uuid,
  p_x integer,
  p_y integer
)
returns table (
  status text,
  next_turn_user_id uuid,
  winner_user_id uuid,
  turn_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_session public.omok_sessions%rowtype;
  target_stone text;
  target_move_no integer;
  other_user_id uuid;
  direction record;
  step integer;
  line_count integer;
  final_status text;
  final_winner uuid;
  next_expires_at timestamptz;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_x not between 0 and 14 or p_y not between 0 and 14 then
    raise exception 'OMOK_MOVE_OUT_OF_BOUNDS';
  end if;

  select * into target_session
  from public.omok_sessions where id = target_session_id
  for update;
  if not found then raise exception 'OMOK_SESSION_NOT_FOUND'; end if;
  if auth.uid() not in (
    target_session.black_user_id,
    target_session.white_user_id
  ) then raise exception 'OMOK_SESSION_FORBIDDEN'; end if;
  if target_session.status <> 'playing' then
    raise exception 'OMOK_SESSION_NOT_PLAYING';
  end if;

  if target_session.turn_expires_at is not null
     and target_session.turn_expires_at <= now() then
    final_winner := case
      when target_session.current_turn_user_id = target_session.black_user_id
        then target_session.white_user_id
      else target_session.black_user_id
    end;
    final_status := case
      when final_winner = target_session.black_user_id
        then 'black_timeout_win'
      else 'white_timeout_win'
    end;
    update public.omok_sessions
    set status = final_status,
        winner_user_id = final_winner,
        current_turn_user_id = null,
        turn_expires_at = null,
        finished_at = now()
    where id = target_session_id;
    return query select final_status, null::uuid, final_winner,
                        null::timestamptz;
    return;
  end if;

  if target_session.current_turn_user_id is distinct from auth.uid() then
    raise exception 'OMOK_NOT_YOUR_TURN';
  end if;
  if exists (
    select 1 from public.omok_moves
    where session_id = target_session_id and x = p_x and y = p_y
  ) then raise exception 'OMOK_CELL_OCCUPIED'; end if;

  target_stone := case
    when auth.uid() = target_session.black_user_id then 'black'
    else 'white'
  end;
  other_user_id := case
    when auth.uid() = target_session.black_user_id
      then target_session.white_user_id
    else target_session.black_user_id
  end;
  select coalesce(max(move_no), 0) + 1 into target_move_no
  from public.omok_moves where session_id = target_session_id;

  insert into public.omok_moves (
    session_id, move_no, user_id, stone, x, y
  ) values (
    target_session_id, target_move_no, auth.uid(), target_stone, p_x, p_y
  );

  final_status := 'playing';
  for direction in
    select * from (values (1, 0), (0, 1), (1, 1), (1, -1))
      as directions(dx, dy)
  loop
    line_count := 1;
    for step in 1..14 loop
      exit when not exists (
        select 1 from public.omok_moves
        where session_id = target_session_id
          and stone = target_stone
          and x = p_x + direction.dx * step
          and y = p_y + direction.dy * step
      );
      line_count := line_count + 1;
    end loop;
    for step in 1..14 loop
      exit when not exists (
        select 1 from public.omok_moves
        where session_id = target_session_id
          and stone = target_stone
          and x = p_x - direction.dx * step
          and y = p_y - direction.dy * step
      );
      line_count := line_count + 1;
    end loop;
    if line_count >= 5 then
      final_winner := auth.uid();
      final_status := case
        when target_stone = 'black' then 'black_win'
        else 'white_win'
      end;
      exit;
    end if;
  end loop;

  if final_status <> 'playing' then
    update public.omok_sessions
    set status = final_status,
        winner_user_id = final_winner,
        current_turn_user_id = null,
        turn_expires_at = null,
        finished_at = now()
    where id = target_session_id;
    return query select final_status, null::uuid, final_winner,
                        null::timestamptz;
    return;
  end if;

  if target_move_no >= 225 then
    update public.omok_sessions
    set status = 'draw',
        winner_user_id = null,
        current_turn_user_id = null,
        turn_expires_at = null,
        finished_at = now()
    where id = target_session_id;
    return query select 'draw'::text, null::uuid, null::uuid,
                        null::timestamptz;
    return;
  end if;

  update public.omok_sessions
  set current_turn_user_id = other_user_id,
      turn_expires_at = now() + interval '30 seconds'
  where id = target_session_id
  returning omok_sessions.turn_expires_at
  into next_expires_at;
  return query select 'playing'::text, other_user_id, null::uuid,
                      next_expires_at;
end;
$$;

create or replace function public.sync_omok_turn_timeout(
  target_session_id uuid
)
returns table (
  status text,
  winner_user_id uuid,
  current_turn_user_id uuid,
  turn_expires_at timestamptz,
  seconds_left integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_session public.omok_sessions%rowtype;
  final_winner uuid;
  final_status text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into target_session
  from public.omok_sessions where id = target_session_id
  for update;
  if not found then raise exception 'OMOK_SESSION_NOT_FOUND'; end if;
  if auth.uid() not in (
    target_session.black_user_id,
    target_session.white_user_id
  ) then raise exception 'OMOK_SESSION_FORBIDDEN'; end if;

  if target_session.status = 'playing'
     and target_session.turn_expires_at is not null
     and target_session.turn_expires_at <= now() then
    final_winner := case
      when target_session.current_turn_user_id = target_session.black_user_id
        then target_session.white_user_id
      else target_session.black_user_id
    end;
    final_status := case
      when final_winner = target_session.black_user_id
        then 'black_timeout_win'
      else 'white_timeout_win'
    end;
    update public.omok_sessions
    set status = final_status,
        winner_user_id = final_winner,
        current_turn_user_id = null,
        turn_expires_at = null,
        finished_at = now()
    where id = target_session_id
    returning * into target_session;
  end if;

  return query select
    target_session.status,
    target_session.winner_user_id,
    target_session.current_turn_user_id,
    target_session.turn_expires_at,
    greatest(
      0,
      ceil(extract(epoch from (
        coalesce(target_session.turn_expires_at, now()) - now()
      )))::integer
    );
end;
$$;

create or replace function public.resign_omok_game(target_session_id uuid)
returns table (status text, winner_user_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  target_session public.omok_sessions%rowtype;
  final_winner uuid;
  final_status text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into target_session
  from public.omok_sessions where id = target_session_id
  for update;
  if not found then raise exception 'OMOK_SESSION_NOT_FOUND'; end if;
  if auth.uid() not in (
    target_session.black_user_id,
    target_session.white_user_id
  ) then raise exception 'OMOK_SESSION_FORBIDDEN'; end if;
  if target_session.status <> 'playing' then
    return query select target_session.status, target_session.winner_user_id;
    return;
  end if;

  final_winner := case
    when auth.uid() = target_session.black_user_id
      then target_session.white_user_id
    else target_session.black_user_id
  end;
  final_status := case
    when final_winner = target_session.black_user_id
      then 'black_resign_win'
    else 'white_resign_win'
  end;
  update public.omok_sessions
  set status = final_status,
      winner_user_id = final_winner,
      current_turn_user_id = null,
      turn_expires_at = null,
      finished_at = now()
  where id = target_session_id;
  return query select final_status, final_winner;
end;
$$;

create or replace function public.create_omok_rematch(target_session_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_session public.omok_sessions%rowtype;
  existing_session_id uuid;
  created_session_id uuid;
  recipient_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into target_session
  from public.omok_sessions where id = target_session_id
  for update;
  if not found then raise exception 'OMOK_SESSION_NOT_FOUND'; end if;
  if auth.uid() not in (
    target_session.black_user_id,
    target_session.white_user_id
  ) then raise exception 'OMOK_SESSION_FORBIDDEN'; end if;
  if target_session.status = 'playing' then
    raise exception 'OMOK_SESSION_STILL_PLAYING';
  end if;

  select id into existing_session_id
  from public.omok_sessions
  where rematch_of_session_id = target_session_id;
  if existing_session_id is not null then return existing_session_id; end if;

  created_session_id := public.create_omok_session_internal(
    target_session.couple_id,
    target_session.white_user_id,
    target_session.black_user_id,
    target_session.id
  );
  recipient_id := case
    when auth.uid() = target_session.black_user_id
      then target_session.white_user_id
    else target_session.black_user_id
  end;
  insert into public.omok_notifications (
    recipient_user_id,
    session_id,
    notification_type,
    actor_user_id
  ) values (
    recipient_id,
    created_session_id,
    'rematch_created',
    auth.uid()
  );
  return created_session_id;
end;
$$;

create or replace function public.get_omok_record(
  target_couple_id uuid,
  target_user_id uuid
)
returns table (
  wins bigint,
  losses bigint,
  draws bigint,
  total_games bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    count(*) filter (where session.winner_user_id = target_user_id),
    count(*) filter (
      where session.status not in ('playing', 'draw', 'cancelled')
        and session.winner_user_id is distinct from target_user_id
    ),
    count(*) filter (where session.status = 'draw'),
    count(*) filter (where session.status <> 'playing')
  from public.omok_sessions session
  where session.couple_id = target_couple_id
    and target_user_id in (session.black_user_id, session.white_user_id)
    and public.current_user_has_couple(target_couple_id);
$$;

create or replace function public.get_omok_recent_games(
  target_couple_id uuid,
  target_user_id uuid,
  p_limit integer default 10
)
returns table (
  session_id uuid,
  status text,
  result text,
  end_reason text,
  winner_user_id uuid,
  finished_at timestamptz,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    session.id,
    session.status,
    case
      when session.status = 'draw' then 'draw'
      when session.status = 'cancelled' then 'cancelled'
      when session.winner_user_id = target_user_id then 'win'
      else 'loss'
    end,
    case
      when session.status in ('black_timeout_win', 'white_timeout_win')
        then 'timeout'
      when session.status in ('black_resign_win', 'white_resign_win')
        then 'resign'
      when session.status = 'draw' then 'draw'
      when session.status = 'cancelled' then 'cancelled'
      else 'five_in_a_row'
    end,
    session.winner_user_id,
    session.finished_at,
    session.created_at
  from public.omok_sessions session
  where session.couple_id = target_couple_id
    and session.status <> 'playing'
    and target_user_id in (session.black_user_id, session.white_user_id)
    and public.current_user_has_couple(target_couple_id)
  order by session.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;

revoke all on function public.generate_omok_invite_code() from public;
revoke all on function public.create_omok_session_internal(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.create_omok_invite() from public;
revoke all on function public.create_omok_push_invite() from public;
revoke all on function public.join_omok_with_invite_code(text) from public;
revoke all on function public.accept_omok_push_invite(uuid) from public;
revoke all on function public.place_omok_move(uuid, integer, integer) from public;
revoke all on function public.sync_omok_turn_timeout(uuid) from public;
revoke all on function public.resign_omok_game(uuid) from public;
revoke all on function public.create_omok_rematch(uuid) from public;
revoke all on function public.get_omok_record(uuid, uuid) from public;
revoke all on function public.get_omok_recent_games(uuid, uuid, integer)
  from public;
grant execute on function public.create_omok_invite() to authenticated;
grant execute on function public.create_omok_push_invite() to authenticated;
grant execute on function public.join_omok_with_invite_code(text)
  to authenticated;
grant execute on function public.accept_omok_push_invite(uuid)
  to authenticated;
grant execute on function public.place_omok_move(uuid, integer, integer)
  to authenticated;
grant execute on function public.sync_omok_turn_timeout(uuid)
  to authenticated;
grant execute on function public.resign_omok_game(uuid) to authenticated;
grant execute on function public.create_omok_rematch(uuid) to authenticated;
grant execute on function public.get_omok_record(uuid, uuid) to authenticated;
grant execute on function public.get_omok_recent_games(uuid, uuid, integer)
  to authenticated;

-- Private storage -----------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit)
values
  ('profile-images', 'profile-images', false, 8388608),
  ('chat-images', 'chat-images', false, 8388608),
  ('memory-album-photos', 'memory-album-photos', false, 8388608),
  ('travel-city-photos', 'travel-city-photos', false, 8388608)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit;

drop policy if exists profile_image_objects_select on storage.objects;
create policy profile_image_objects_select on storage.objects for select
using (
  bucket_id = 'profile-images'
  and case
    when (storage.foldername(name))[1] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    then public.current_user_can_view_profile(
      ((storage.foldername(name))[1])::uuid
    )
    else false
  end
);
drop policy if exists profile_image_objects_insert on storage.objects;
create policy profile_image_objects_insert on storage.objects for insert
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name ~* '\.(jpg|jpeg|png|webp)$'
);
drop policy if exists profile_image_objects_update on storage.objects;
create policy profile_image_objects_update on storage.objects for update
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
drop policy if exists profile_image_objects_delete on storage.objects;
create policy profile_image_objects_delete on storage.objects for delete
using (
  bucket_id = 'profile-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists chat_image_objects_select on storage.objects;
create policy chat_image_objects_select on storage.objects for select
using (
  bucket_id = 'chat-images'
  and case
    when (storage.foldername(name))[1] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    then public.current_user_has_couple(
      ((storage.foldername(name))[1])::uuid
    )
    else false
  end
);
drop policy if exists chat_image_objects_insert on storage.objects;
create policy chat_image_objects_insert on storage.objects for insert
with check (
  bucket_id = 'chat-images'
  and name ~* '\.(jpg|jpeg|png|webp)$'
  and case
    when (storage.foldername(name))[1] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    then public.current_user_has_couple(
      ((storage.foldername(name))[1])::uuid
    )
    else false
  end
);
drop policy if exists chat_image_objects_delete on storage.objects;
create policy chat_image_objects_delete on storage.objects for delete
using (
  bucket_id = 'chat-images'
  and case
    when (storage.foldername(name))[1] ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    then public.current_user_has_couple(
      ((storage.foldername(name))[1])::uuid
    )
    else false
  end
);

drop policy if exists memory_album_photo_objects_select on storage.objects;
create policy memory_album_photo_objects_select on storage.objects for select
using (
  bucket_id = 'memory-album-photos'
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
drop policy if exists memory_album_photo_objects_insert on storage.objects;
create policy memory_album_photo_objects_insert on storage.objects for insert
with check (
  bucket_id = 'memory-album-photos'
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
drop policy if exists memory_album_photo_objects_delete on storage.objects;
create policy memory_album_photo_objects_delete on storage.objects for delete
using (
  bucket_id = 'memory-album-photos'
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

drop policy if exists travel_city_photo_objects_select on storage.objects;
create policy travel_city_photo_objects_select on storage.objects for select
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
drop policy if exists travel_city_photo_objects_insert on storage.objects;
create policy travel_city_photo_objects_insert on storage.objects for insert
with check (
  bucket_id = 'travel-city-photos'
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
drop policy if exists travel_city_photo_objects_delete on storage.objects;
create policy travel_city_photo_objects_delete on storage.objects for delete
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

-- Keep direct table privileges narrow.  Security-definer RPCs own pairing and
-- all game mutations; clients only edit the columns exposed by the app.
revoke insert, delete on public.couples from authenticated;
revoke update on public.couples from authenticated;
grant select on public.couples to authenticated;
grant update(anniversary_date) on public.couples to authenticated;
revoke insert, delete on public.profiles from authenticated;
revoke update on public.profiles from authenticated;
grant select on public.profiles to authenticated;
grant update(nickname, avatar_path) on public.profiles to authenticated;

grant select, insert, delete on public.messages to authenticated;
grant usage, select on sequence public.messages_id_seq to authenticated;
grant select, insert, delete on public.message_reactions to authenticated;
grant usage, select on sequence public.message_reactions_id_seq to authenticated;
grant select, insert, update, delete on public.anniversaries to authenticated;
grant select, insert, update, delete on public.memory_albums to authenticated;
grant select, insert, update, delete on public.memory_album_photos
  to authenticated;
grant select on public.travel_cities, public.world_countries to authenticated;
grant select, insert, update, delete on public.travel_city_visits
  to authenticated;
grant select, insert, delete on public.travel_city_photos to authenticated;
grant select, insert, update, delete on public.world_country_visits
  to authenticated;
grant select on public.omok_sessions, public.omok_invites, public.omok_moves
  to authenticated;
grant select, update(read_at) on public.omok_notifications to authenticated;
grant select, insert, update, delete on public.device_push_tokens
  to authenticated;

-- Realtime ------------------------------------------------------------------

do $$
declare
  realtime_table text;
begin
  if not exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    execute 'create publication supabase_realtime';
  end if;

  foreach realtime_table in array array[
    'profiles',
    'messages',
    'message_reactions',
    'anniversaries',
    'memory_albums',
    'memory_album_photos',
    'travel_city_visits',
    'travel_city_photos',
    'world_country_visits',
    'omok_sessions',
    'omok_invites',
    'omok_moves',
    'omok_notifications'
  ]
  loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = realtime_table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        realtime_table
      );
    end if;
  end loop;
end;
$$;

commit;
