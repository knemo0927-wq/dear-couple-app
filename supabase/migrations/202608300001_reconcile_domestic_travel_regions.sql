begin;

-- Reconcile the complete domestic map catalog by its stable public code.
-- Existing travel_cities identities remain in place so visits and photos keep
-- pointing at the same rows while catalog metadata is repaired.
create temporary table canonical_travel_cities (
  code text primary key,
  name text not null,
  region_group text not null,
  center_lat double precision not null,
  center_lng double precision not null,
  sort_order integer not null unique
) on commit drop;

insert into canonical_travel_cities (
  code, name, region_group, center_lat, center_lng, sort_order
)
values
  ('METRO_11', '서울', '서울', 37.566500, 126.978000, 1),
  ('METRO_21', '부산', '부산', 35.179600, 129.075600, 2),
  ('METRO_22', '대구', '대구', 35.871400, 128.601400, 3),
  ('METRO_23', '인천', '인천', 37.456300, 126.705200, 4),
  ('METRO_24', '광주', '광주', 35.159500, 126.852600, 5),
  ('METRO_25', '대전', '대전', 36.350400, 127.384500, 6),
  ('METRO_26', '울산', '울산', 35.538400, 129.311400, 7),
  ('METRO_29', '세종', '세종', 36.480000, 127.289000, 8),
  ('SIG_31014', '수원', '경기', 37.259600, 127.046000, 9),
  ('SIG_31104', '고양', '경기', 37.675000, 126.755000, 10),
  ('SIG_31193', '용인', '경기', 37.322000, 127.097000, 11),
  ('SIG_31023', '성남', '경기', 37.382800, 127.118900, 12),
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
  ('SIG_39020', '서귀포', '제주', 33.315318, 126.548098, 40),
  ('SIG_31030', '의정부', '경기', 37.736201, 127.068450, 41),
  ('SIG_31041', '안양', '경기', 37.402764, 126.927957, 42),
  ('SIG_31051', '부천', '경기', 37.504257, 126.788653, 43),
  ('SIG_31060', '광명', '경기', 37.445087, 126.864690, 44),
  ('SIG_31070', '평택', '경기', 37.015339, 126.993191, 45),
  ('SIG_31080', '동두천', '경기', 37.916542, 127.077876, 46),
  ('SIG_31091', '안산', '경기', 37.290802, 126.747054, 47),
  ('SIG_31110', '과천', '경기', 37.433855, 127.002736, 48),
  ('SIG_31120', '구리', '경기', 37.599178, 127.131252, 49),
  ('SIG_31130', '남양주', '경기', 37.662556, 127.243632, 50),
  ('SIG_31140', '오산', '경기', 37.163315, 127.051308, 51),
  ('SIG_31150', '시흥', '경기', 37.386122, 126.783684, 52),
  ('SIG_31160', '군포', '경기', 37.343483, 126.921096, 53),
  ('SIG_31170', '의왕', '경기', 37.362402, 126.989626, 54),
  ('SIG_31180', '하남', '경기', 37.522797, 127.205942, 55),
  ('SIG_31200', '파주', '경기', 37.855565, 126.809514, 56),
  ('SIG_31210', '이천', '경기', 37.209822, 127.480947, 57),
  ('SIG_31220', '안성', '경기', 37.035014, 127.302763, 58),
  ('SIG_31230', '김포', '경기', 37.680875, 126.625773, 59),
  ('SIG_31240', '화성', '경기', 37.169847, 126.856861, 60),
  ('SIG_31250', '광주', '경기', 37.403129, 127.301190, 61),
  ('SIG_31260', '양주', '경기', 37.808709, 127.001160, 62),
  ('SIG_31270', '포천', '경기', 37.969880, 127.250435, 63),
  ('SIG_31280', '여주', '경기', 37.302515, 127.615691, 64),
  ('SIG_31550', '연천', '경기', 38.097059, 127.023935, 65),
  ('SIG_31580', '양평', '경기', 37.518040, 127.579184, 66),
  ('SIG_32040', '동해', '강원', 37.506890, 129.055700, 67),
  ('SIG_32050', '태백', '강원', 37.172349, 128.980073, 68),
  ('SIG_32070', '삼척', '강원', 37.277536, 129.122074, 69),
  ('SIG_32510', '홍천', '강원', 37.744866, 128.074513, 70),
  ('SIG_32520', '횡성', '강원', 37.508983, 128.077129, 71),
  ('SIG_32530', '영월', '강원', 37.203917, 128.500288, 72),
  ('SIG_32550', '정선', '강원', 37.378768, 128.739053, 73),
  ('SIG_32560', '철원', '강원', 38.243788, 127.413511, 74),
  ('SIG_32570', '화천', '강원', 38.138436, 127.685198, 75),
  ('SIG_32580', '양구', '강원', 38.178105, 128.001218, 76),
  ('SIG_32590', '인제', '강원', 38.069005, 128.263309, 77),
  ('SIG_32600', '고성', '강원', 38.377355, 128.399859, 78),
  ('SIG_33520', '보은', '충북', 36.489948, 127.729338, 79),
  ('SIG_33530', '옥천', '충북', 36.320443, 127.656569, 80),
  ('SIG_33540', '영동', '충북', 36.159689, 127.814236, 81),
  ('SIG_33550', '진천', '충북', 36.871005, 127.440434, 82),
  ('SIG_33560', '괴산', '충북', 36.769722, 127.829596, 83),
  ('SIG_33570', '음성', '충북', 36.976260, 127.614158, 84),
  ('SIG_33580', '단양', '충북', 36.994506, 128.387884, 85),
  ('SIG_33590', '증평', '충북', 36.786488, 127.604609, 86),
  ('SIG_34040', '아산', '충남', 36.807381, 126.980069, 87),
  ('SIG_34050', '서산', '충남', 36.784917, 126.463165, 88),
  ('SIG_34060', '논산', '충남', 36.190913, 127.157769, 89),
  ('SIG_34070', '계룡', '충남', 36.291703, 127.234352, 90),
  ('SIG_34080', '당진', '충남', 36.904398, 126.652264, 91),
  ('SIG_34510', '금산', '충남', 36.119014, 127.478265, 92),
  ('SIG_34530', '부여', '충남', 36.246372, 126.856939, 93),
  ('SIG_34540', '서천', '충남', 36.106814, 126.703724, 94),
  ('SIG_34550', '청양', '충남', 36.430596, 126.853048, 95),
  ('SIG_34560', '홍성', '충남', 36.570064, 126.625815, 96),
  ('SIG_34570', '예산', '충남', 36.670652, 126.784297, 97),
  ('SIG_34580', '태안', '충남', 36.707682, 126.280107, 98),
  ('SIG_35030', '익산', '전북', 36.023157, 126.989530, 99),
  ('SIG_35040', '정읍', '전북', 35.602604, 126.905855, 100),
  ('SIG_35060', '김제', '전북', 35.806706, 126.894603, 101),
  ('SIG_35510', '완주', '전북', 35.918698, 127.215202, 102),
  ('SIG_35520', '진안', '전북', 35.828882, 127.430063, 103),
  ('SIG_35530', '무주', '전북', 35.939381, 127.712970, 104),
  ('SIG_35540', '장수', '전북', 35.657513, 127.544323, 105),
  ('SIG_35550', '임실', '전북', 35.598230, 127.236636, 106),
  ('SIG_35560', '순창', '전북', 35.433624, 127.090101, 107),
  ('SIG_35570', '고창', '전북', 35.449031, 126.615860, 108),
  ('SIG_35580', '부안', '전북', 35.685138, 126.640495, 109),
  ('SIG_36040', '나주', '전남', 34.988574, 126.720431, 110),
  ('SIG_36060', '광양', '전남', 35.018903, 127.656046, 111),
  ('SIG_36510', '담양', '전남', 35.291593, 126.995229, 112),
  ('SIG_36520', '곡성', '전남', 35.216628, 127.263526, 113),
  ('SIG_36530', '구례', '전남', 35.236778, 127.503087, 114),
  ('SIG_36550', '고흥', '전남', 34.598530, 127.314576, 115),
  ('SIG_36560', '보성', '전남', 34.814256, 127.162439, 116),
  ('SIG_36570', '화순', '전남', 35.008269, 127.033534, 117),
  ('SIG_36580', '장흥', '전남', 34.675296, 126.921980, 118),
  ('SIG_36590', '강진', '전남', 34.620281, 126.772186, 119),
  ('SIG_36600', '해남', '전남', 34.558558, 126.511467, 120),
  ('SIG_36610', '영암', '전남', 34.796011, 126.623670, 121),
  ('SIG_36620', '무안', '전남', 34.953861, 126.425140, 122),
  ('SIG_36630', '함평', '전남', 35.112671, 126.535498, 123),
  ('SIG_36640', '영광', '전남', 35.278922, 126.450910, 124),
  ('SIG_36650', '장성', '전남', 35.329598, 126.768621, 125),
  ('SIG_36660', '완도', '전남', 34.294682, 126.777875, 126),
  ('SIG_36670', '진도', '전남', 34.437788, 126.212909, 127),
  ('SIG_36680', '신안', '전남', 34.810471, 126.043853, 128),
  ('SIG_37030', '김천', '경북', 36.060524, 128.077824, 129),
  ('SIG_37050', '구미', '경북', 36.207376, 128.355449, 130),
  ('SIG_37060', '영주', '경북', 36.870571, 128.597641, 131),
  ('SIG_37070', '영천', '경북', 36.015816, 128.942632, 132),
  ('SIG_37080', '상주', '경북', 36.429571, 128.066988, 133),
  ('SIG_37090', '문경', '경북', 36.690803, 128.148713, 134),
  ('SIG_37100', '경산', '경북', 35.834150, 128.809027, 135),
  ('SIG_37520', '의성', '경북', 36.362027, 128.614884, 136),
  ('SIG_37530', '청송', '경북', 36.357027, 129.057425, 137),
  ('SIG_37540', '영양', '경북', 36.696461, 129.145053, 138),
  ('SIG_37550', '영덕', '경북', 36.482484, 129.317622, 139),
  ('SIG_37560', '청도', '경북', 35.672927, 128.786576, 140),
  ('SIG_37570', '고령', '경북', 35.737198, 128.306748, 141),
  ('SIG_37580', '성주', '경북', 35.907269, 128.233381, 142),
  ('SIG_37590', '칠곡', '경북', 36.015525, 128.462546, 143),
  ('SIG_37600', '예천', '경북', 36.653913, 128.422495, 144),
  ('SIG_37610', '봉화', '경북', 36.934161, 128.912987, 145),
  ('SIG_37620', '울진', '경북', 36.904089, 129.312462, 146),
  ('SIG_37630', '울릉', '경북', 37.501930, 130.863000, 147),
  ('SIG_38030', '진주', '경남', 35.205155, 128.129779, 148),
  ('SIG_38060', '사천', '경남', 35.049533, 128.037505, 149),
  ('SIG_38080', '밀양', '경남', 35.498503, 128.789623, 150),
  ('SIG_38100', '양산', '경남', 35.401916, 129.041050, 151),
  ('SIG_38510', '의령', '경남', 35.392459, 128.277107, 152),
  ('SIG_38520', '함안', '경남', 35.290999, 128.430897, 153),
  ('SIG_38530', '창녕', '경남', 35.508379, 128.492912, 154),
  ('SIG_38540', '고성', '경남', 35.016077, 128.290590, 155),
  ('SIG_38550', '남해', '경남', 34.818172, 127.941428, 156),
  ('SIG_38560', '하동', '경남', 35.137608, 127.779129, 157),
  ('SIG_38570', '산청', '경남', 35.368647, 127.884364, 158),
  ('SIG_38580', '함양', '경남', 35.551734, 127.722069, 159),
  ('SIG_38590', '거창', '경남', 35.732615, 127.904118, 160),
  ('SIG_38600', '합천', '경남', 35.576670, 128.141543, 161);

do $$
declare
  canonical_count integer;
  canonical_sort_count integer;
  canonical_min_sort integer;
  canonical_max_sort integer;
begin
  select count(*), count(distinct sort_order), min(sort_order), max(sort_order)
  into canonical_count, canonical_sort_count, canonical_min_sort,
       canonical_max_sort
  from canonical_travel_cities;

  if canonical_count <> 161
     or canonical_sort_count <> 161
     or canonical_min_sort <> 1
     or canonical_max_sort <> 161 then
    raise exception using
      errcode = '23514',
      message = format(
        'Domestic travel canonical seed is invalid: rows=%s distinct_sort=%s range=%s..%s',
        canonical_count,
        canonical_sort_count,
        canonical_min_sort,
        canonical_max_sort
      );
  end if;
end;
$$;

lock table public.travel_cities in share row exclusive mode;

-- Some deployed projects predate the stable METRO_/SIG_ catalog and still
-- use CITY_* codes or an older SGIS code revision. Re-key those rows in place
-- so their UUIDs (and therefore visit/photo foreign keys) remain unchanged.
create temporary table legacy_travel_city_mapping (
  source_city_id uuid primary key,
  source_code text not null unique,
  target_code text not null unique,
  mapping_distance double precision not null
) on commit drop;

insert into legacy_travel_city_mapping (
  source_city_id, source_code, target_code, mapping_distance
)
select
  actual.id,
  actual.code,
  target.code,
  target.mapping_distance
from public.travel_cities as actual
join lateral (
  select
    canonical.code,
    sqrt(
      power(actual.center_lat - canonical.center_lat, 2) +
      power(actual.center_lng - canonical.center_lng, 2)
    ) as mapping_distance
  from canonical_travel_cities as canonical
  where actual.name = canonical.name
     or regexp_replace(actual.name, '(시|군|구)$', '') = canonical.name
  order by
    (actual.name = canonical.name) desc,
    power(actual.center_lat - canonical.center_lat, 2) +
      power(actual.center_lng - canonical.center_lng, 2),
    canonical.sort_order
  limit 1
) as target on true
where not exists (
  select 1
  from canonical_travel_cities as canonical
  where canonical.code = actual.code
);

do $$
declare
  unexpected_source_count integer;
  mapped_source_count integer;
  mapped_target_count integer;
  duplicate_target_count integer;
  existing_target_count integer;
  max_mapping_distance double precision;
begin
  select count(*)
  into unexpected_source_count
  from public.travel_cities as actual
  where not exists (
    select 1
    from canonical_travel_cities as canonical
    where canonical.code = actual.code
  );

  select count(*), count(distinct target_code)
  into mapped_source_count, mapped_target_count
  from legacy_travel_city_mapping;

  select count(*)
  into duplicate_target_count
  from (
    select target_code
    from legacy_travel_city_mapping
    group by target_code
    having count(*) > 1
  ) as duplicate_targets;

  select count(*)
  into existing_target_count
  from legacy_travel_city_mapping as mapping
  join public.travel_cities as existing
    on existing.code = mapping.target_code;

  select max(mapping_distance)
  into max_mapping_distance
  from legacy_travel_city_mapping;

  if unexpected_source_count <> mapped_source_count
     or mapped_target_count <> mapped_source_count
     or duplicate_target_count <> 0
     or existing_target_count <> 0
     or max_mapping_distance > 0.15 then
    raise exception using
      errcode = '23514',
      message = format(
        'Domestic travel legacy mapping is unsafe: unexpected=%s mapped=%s distinct_targets=%s duplicate_targets=%s existing_targets=%s max_distance=%s',
        unexpected_source_count,
        mapped_source_count,
        mapped_target_count,
        duplicate_target_count,
        existing_target_count,
        max_mapping_distance
      );
  end if;
end;
$$;

update public.travel_cities as actual
set code = mapping.target_code,
    name = canonical.name,
    region_group = canonical.region_group,
    center_lat = canonical.center_lat,
    center_lng = canonical.center_lng,
    sort_order = canonical.sort_order
from legacy_travel_city_mapping as mapping
join canonical_travel_cities as canonical
  on canonical.code = mapping.target_code
where actual.id = mapping.source_city_id;

insert into public.travel_cities (
  code, name, region_group, center_lat, center_lng, sort_order
)
select code, name, region_group, center_lat, center_lng, sort_order
from canonical_travel_cities
order by sort_order
on conflict (code) do update
set name = excluded.name,
    region_group = excluded.region_group,
    center_lat = excluded.center_lat,
    center_lng = excluded.center_lng,
    sort_order = excluded.sort_order;

do $$
declare
  actual_count integer;
  actual_sort_count integer;
  actual_min_sort integer;
  actual_max_sort integer;
  missing_code_count integer;
  unexpected_code_count integer;
  mismatched_value_count integer;
  remapped_identity_mismatch_count integer;
begin
  select count(*), count(distinct sort_order), min(sort_order), max(sort_order)
  into actual_count, actual_sort_count, actual_min_sort, actual_max_sort
  from public.travel_cities;

  select count(*)
  into missing_code_count
  from canonical_travel_cities as canonical
  where not exists (
    select 1
    from public.travel_cities as actual
    where actual.code = canonical.code
  );

  select count(*)
  into unexpected_code_count
  from public.travel_cities as actual
  where not exists (
    select 1
    from canonical_travel_cities as canonical
    where canonical.code = actual.code
  );

  select count(*)
  into mismatched_value_count
  from canonical_travel_cities as canonical
  join public.travel_cities as actual using (code)
  where actual.name is distinct from canonical.name
     or actual.region_group is distinct from canonical.region_group
     or actual.center_lat is distinct from canonical.center_lat
     or actual.center_lng is distinct from canonical.center_lng
     or actual.sort_order is distinct from canonical.sort_order;

  select count(*)
  into remapped_identity_mismatch_count
  from legacy_travel_city_mapping as mapping
  left join public.travel_cities as actual
    on actual.code = mapping.target_code
  where actual.id is distinct from mapping.source_city_id;

  if actual_count <> 161
     or actual_sort_count <> 161
     or actual_min_sort <> 1
     or actual_max_sort <> 161
     or missing_code_count <> 0
     or unexpected_code_count <> 0
     or mismatched_value_count <> 0
     or remapped_identity_mismatch_count <> 0 then
    raise exception using
      errcode = '23514',
      message = format(
        'Domestic travel catalog reconciliation failed: rows=%s distinct_sort=%s range=%s..%s missing=%s unexpected=%s mismatched=%s remapped_identity_mismatches=%s',
        actual_count,
        actual_sort_count,
        actual_min_sort,
        actual_max_sort,
        missing_code_count,
        unexpected_code_count,
        mismatched_value_count,
        remapped_identity_mismatch_count
      );
  end if;
end;
$$;

commit;
