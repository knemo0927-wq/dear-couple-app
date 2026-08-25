import 'dart:convert';
import 'dart:io';

import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/widgets/korea_city_map_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('matchTravelCityForKoreaAdministrativeRegion', () {
    test('광주광역시와 경기 광주시는 이름이 같아도 코드로 구분한다', () {
      final seoul = _city(code: 'METRO_11', name: '서울');
      final metroGwangju = _city(code: 'METRO_24', name: '광주');
      final gyeonggiGwangju = _city(code: 'SIG_31250', name: '광주');
      final cities = [seoul, metroGwangju, gyeonggiGwangju];

      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '11010',
          name: '종로구',
          cities: cities,
        ),
        same(seoul),
      );
      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '11250',
          name: '강동구',
          cities: cities,
        ),
        same(seoul),
      );
      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '24010',
          name: '동구',
          cities: cities,
        ),
        same(metroGwangju),
      );
      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '31250',
          name: '광주시',
          cities: cities,
        ),
        same(gyeonggiGwangju),
      );
    });

    test('수원 4개 구는 하나의 여행 도시로 매핑하고 화성은 제외한다', () {
      final suwon = _city(code: 'SIG_31014', name: '수원');
      final cities = [suwon];
      const suwonRegions = {
        '31011': '수원시 장안구',
        '31012': '수원시 권선구',
        '31013': '수원시 팔달구',
        '31014': '수원시 영통구',
      };

      for (final region in suwonRegions.entries) {
        expect(
          matchTravelCityForKoreaAdministrativeRegion(
            code: region.key,
            name: region.value,
            cities: cities,
          ),
          same(suwon),
          reason: '${region.key} ${region.value}',
        );
      }
      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '31240',
          name: '화성시',
          cities: cities,
        ),
        isNull,
      );
    });

    test('legacy 청주 seed는 현행 4개 구 경계와 모두 매핑된다', () {
      final cheongju = _city(code: 'SIG_33011', name: '청주');
      final cities = [cheongju];
      const cheongjuRegions = {
        '33041': '청주시 상당구',
        '33042': '청주시 서원구',
        '33043': '청주시 흥덕구',
        '33044': '청주시 청원구',
      };

      for (final region in cheongjuRegions.entries) {
        expect(
          matchTravelCityForKoreaAdministrativeRegion(
            code: region.key,
            name: region.value,
            cities: cities,
          ),
          same(cheongju),
          reason: '${region.key} ${region.value}',
        );
      }
    });

    test('대구 metro에 2023년 편입된 군위군을 포함한다', () {
      final daegu = _city(code: 'METRO_22', name: '대구');

      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '22520',
          name: '군위군',
          cities: [daegu],
        ),
        same(daegu),
      );
    });

    test('안양의 두 행정구는 하나의 여행 지역으로 매핑한다', () {
      final anyang = _city(code: 'SIG_31041', name: '안양');

      for (final code in ['31041', '31042']) {
        expect(
          matchTravelCityForKoreaAdministrativeRegion(
            code: code,
            name: code == '31041' ? '안양시 만안구' : '안양시 동안구',
            cities: [anyang],
          ),
          same(anyang),
        );
      }
    });

    test('강원 고성과 경남 고성은 동명이지만 각각의 SIG 코드로 구분한다', () {
      final gangwonGoseong = _city(code: 'SIG_32600', name: '고성');
      final gyeongnamGoseong = _city(code: 'SIG_38540', name: '고성');
      final cities = [gangwonGoseong, gyeongnamGoseong];

      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '32600',
          name: '고성군',
          cities: cities,
        ),
        same(gangwonGoseong),
      );
      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '38540',
          name: '고성군',
          cities: cities,
        ),
        same(gyeongnamGoseong),
      );
    });

    test('미지원 시군은 가장 가까운 여행 도시로 대체하지 않는다', () {
      final nearbySupportedCities = [
        _city(code: 'SIG_38111', name: '창원'),
        _city(code: 'SIG_38070', name: '김해'),
        _city(code: 'SIG_38090', name: '거제'),
      ];

      expect(
        matchTravelCityForKoreaAdministrativeRegion(
          code: '38600',
          name: '합천군',
          cities: nearbySupportedCities,
        ),
        isNull,
      );
    });
  });

  group('official Korea municipality GeoJSON', () {
    late Map<String, dynamic> geoJson;
    late List<dynamic> features;

    setUpAll(() async {
      final raw = await File(
        'assets/maps/skorea_municipalities_geo_simple.json',
      ).readAsString();
      geoJson = jsonDecode(raw) as Map<String, dynamic>;
      features = geoJson['features'] as List<dynamic>;
    });

    test('2025-06-30 기준 252개 행정구역을 중복 코드 없이 담는다', () {
      expect(geoJson['type'], 'FeatureCollection');
      expect(features, hasLength(252));

      final codes = <String>{};
      for (final rawFeature in features) {
        final feature = rawFeature as Map<String, dynamic>;
        final properties = feature['properties'] as Map<String, dynamic>;
        final code = properties['code'] as String;

        expect(code, matches(RegExp(r'^\d{5}$')));
        expect(
          codes.add(code),
          isTrue,
          reason: '중복된 행정구역 코드: $code',
        );
        expect(
          properties['base_date'],
          '20250630',
          reason: '$code ${properties['name']}',
        );
      }
    });

    test('모든 geometry는 폐합된 유한 좌표의 Polygon 또는 MultiPolygon이다', () {
      for (final rawFeature in features) {
        final feature = rawFeature as Map<String, dynamic>;
        final properties = feature['properties'] as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>;
        final type = geometry['type'];
        final coordinates = geometry['coordinates'];
        final reason = '${properties['code']} ${properties['name']}';

        expect(type, anyOf('Polygon', 'MultiPolygon'), reason: reason);
        if (type == 'Polygon') {
          _expectValidPolygon(coordinates, reason: reason);
        } else {
          expect(coordinates, isA<List<dynamic>>(), reason: reason);
          final polygons = coordinates as List<dynamic>;
          expect(polygons, isNotEmpty, reason: reason);
          for (final polygon in polygons) {
            _expectValidPolygon(polygon, reason: reason);
          }
        }
      }
    });

    test('최신 행정구역 변경 표본을 포함한다', () {
      final nameByCode = <String, String>{
        for (final rawFeature in features)
          (rawFeature as Map<String, dynamic>)['properties']['code'] as String:
              rawFeature['properties']['name'] as String,
      };

      expect(nameByCode['22520'], '군위군');
      expect(nameByCode['23090'], '미추홀구');
      expect(nameByCode['33041'], '청주시 상당구');
      expect(nameByCode['33042'], '청주시 서원구');
      expect(nameByCode['33043'], '청주시 흥덕구');
      expect(nameByCode['33044'], '청주시 청원구');
    });

    test('독도와 마라도를 포함한 공식 경계 최외곽을 유지한다', () {
      var minLatitude = double.infinity;
      var maxLongitude = -double.infinity;

      for (final rawFeature in features) {
        final feature = rawFeature as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>;
        _visitCoordinates(geometry['coordinates'], (longitude, latitude) {
          minLatitude = latitude < minLatitude ? latitude : minLatitude;
          maxLongitude = longitude > maxLongitude ? longitude : maxLongitude;
        });
      }

      expect(minLatitude, lessThan(33.12), reason: '마라도 경계가 누락됨');
      expect(maxLongitude, greaterThan(131.87), reason: '독도 경계가 누락됨');
    });

    test('공식 출처와 가공 기준을 저장소에 기록한다', () async {
      final provenance = await File('assets/maps/README.md').readAsString();

      expect(provenance, contains('2025-06-30'));
      expect(provenance, contains('EPSG:5179'));
      expect(provenance, contains('EPSG:4326'));
      expect(provenance, contains('이용허락범위 제한 없음'));
      expect(provenance, contains('1%'));
      expect(provenance, contains('161 travel regions'));
    });

    test('기존 40개에 121개를 추가하는 마이그레이션은 기록을 보존한다', () {
      final baselineCities = _seedCitiesFromMigration(
        'supabase/migrations/202607110000_dear_baseline.sql',
      );
      const expansionPath =
          'supabase/migrations/202607140002_expand_domestic_travel_regions.sql';
      final expansionSql = File(expansionPath).readAsStringSync();
      final expansionCities = _seedCitiesFromMigration(expansionPath);

      expect(baselineCities, hasLength(40));
      expect(expansionCities, hasLength(121));
      expect(
        baselineCities.map((city) => city.code).toSet().intersection(
              expansionCities.map((city) => city.code).toSet(),
            ),
        isEmpty,
      );
      expect(expansionSql.trimLeft(), startsWith('begin;'));
      expect(expansionSql.trimRight(), endsWith('commit;'));
      expect(expansionSql, contains('on conflict (code) do update'));
      expect(
        expansionSql,
        isNot(
          matches(
            RegExp(r'\b(delete|truncate)\b', caseSensitive: false),
          ),
        ),
      );
      expect(expansionSql, isNot(contains('id = excluded.id')));

      final allCities = [...baselineCities, ...expansionCities];
      expect(allCities.map((city) => city.code).toSet(), hasLength(161));
      expect(allCities.map((city) => city.sortOrder).toSet(), hasLength(161));
      expect(
        allCities.map((city) => city.sortOrder).toList()..sort(),
        orderedEquals(List<int>.generate(161, (index) => index + 1)),
      );
      for (final city in expansionCities) {
        expect(city.centerLat, inInclusiveRange(33.03, 38.70));
        expect(city.centerLng, inInclusiveRange(124.53, 131.96));
      }
    });

    test('161개 여행 지역이 252개 공식 경계를 빠짐없이 한 번씩 배정한다', () {
      final cities = _allTravelCities();
      final featureCountByCityId = <String, int>{};

      for (final rawFeature in features) {
        final feature = rawFeature as Map<String, dynamic>;
        final properties = feature['properties'] as Map<String, dynamic>;
        final code = properties['code'] as String;
        final name = properties['name'] as String;
        final matchedCities = <TravelCity>[
          for (final city in cities)
            if (matchTravelCityForKoreaAdministrativeRegion(
                  code: code,
                  name: name,
                  cities: [city],
                ) !=
                null)
              city,
        ];

        expect(
          matchedCities.length,
          1,
          reason: '$code $name 중복 귀속: ${matchedCities.map((e) => e.name)}',
        );
        featureCountByCityId.update(
          matchedCities.single.id,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }

      expect(cities, hasLength(161));
      expect(featureCountByCityId, hasLength(161));
      expect(
        featureCountByCityId.values.fold<int>(0, (sum, count) => sum + count),
        252,
      );
      expect(featureCountByCityId['METRO_11'], 25);
      expect(featureCountByCityId['METRO_22'], 9);
      expect(featureCountByCityId['SIG_31014'], 4);
      expect(featureCountByCityId['SIG_31041'], 2);
      expect(featureCountByCityId['SIG_31051'], 3);
      expect(featureCountByCityId['SIG_31091'], 2);
      expect(featureCountByCityId['SIG_33011'], 4);
      expect(featureCountByCityId['SIG_38111'], 5);

      final countByRegionGroup = <String, int>{};
      for (final city in cities) {
        countByRegionGroup.update(
          city.regionGroup,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      expect(countByRegionGroup, {
        '서울': 1,
        '부산': 1,
        '대구': 1,
        '인천': 1,
        '광주': 1,
        '대전': 1,
        '울산': 1,
        '세종': 1,
        '경기': 31,
        '강원': 18,
        '충북': 11,
        '충남': 15,
        '전북': 14,
        '전남': 22,
        '경북': 22,
        '경남': 18,
        '제주': 2,
      });
    });
  });

  group('projectKoreaLocationToCanvas', () {
    const canvasSize = Size(360, 520);

    test('대표 지점을 canvas 영역 안에 투영한다', () {
      final cities = [
        _city(code: 'METRO_11', name: '서울'),
        _city(code: 'METRO_21', name: '부산'),
        _city(code: 'SIG_39010', name: '제주'),
        _city(code: 'SIG_32060', name: '속초'),
      ];
      const representativeLocations = {
        '서울': (latitude: 37.5665, longitude: 126.9780),
        '부산': (latitude: 35.1796, longitude: 129.0756),
        '제주': (latitude: 33.4996, longitude: 126.5312),
        '속초': (latitude: 38.2070, longitude: 128.5918),
      };

      for (final location in representativeLocations.entries) {
        final point = projectKoreaLocationToCanvas(
          size: canvasSize,
          cities: cities,
          latitude: location.value.latitude,
          longitude: location.value.longitude,
        );

        expect(point.dx, inInclusiveRange(0, canvasSize.width),
            reason: location.key);
        expect(point.dy, inInclusiveRange(0, canvasSize.height),
            reason: location.key);
      }
    });

    test('투영 결과는 여행 도시 목록이 아닌 공식 지도 bounds를 사용한다', () {
      final seoulOnly = [_city(code: 'METRO_11', name: '서울')];
      final nationwideCities = [
        ...seoulOnly,
        _city(code: 'METRO_21', name: '부산'),
        _city(code: 'SIG_39010', name: '제주'),
        _city(code: 'SIG_32060', name: '속초'),
      ];

      final projectedWithOneCity = projectKoreaLocationToCanvas(
        size: canvasSize,
        cities: seoulOnly,
        latitude: 36.3504,
        longitude: 127.3845,
      );
      final projectedWithAllCities = projectKoreaLocationToCanvas(
        size: canvasSize,
        cities: nationwideCities,
        latitude: 36.3504,
        longitude: 127.3845,
      );

      expect(projectedWithOneCity.dx, closeTo(projectedWithAllCities.dx, 1e-9));
      expect(projectedWithOneCity.dy, closeTo(projectedWithAllCities.dy, 1e-9));
    });

    test('Web Mercator에서 같은 위도 차이는 북쪽일수록 더 넓게 투영된다', () {
      final cities = [_city(code: 'METRO_11', name: '서울')];
      Offset project(double latitude) => projectKoreaLocationToCanvas(
            size: canvasSize,
            cities: cities,
            latitude: latitude,
            longitude: 127.5,
          );

      final southernDegree = project(34).dy - project(35).dy;
      final northernDegree = project(37).dy - project(38).dy;

      expect(southernDegree, greaterThan(0));
      expect(northernDegree, greaterThan(southernDegree));
    });
  });

  testWidgets('신규 지역은 선택되고 목록 밖 지역은 가까운 도시로 대체되지 않는다', (tester) async {
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final suwon = _city(code: 'SIG_31014', name: '수원');
    final hwaseong = _city(code: 'SIG_31240', name: '화성');
    final cities = [suwon, hwaseong];
    var tapCount = 0;
    TravelCity? tappedCity;
    const mapKey = ValueKey('korea-map-hit-test');

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            key: mapKey,
            width: 360,
            height: 520,
            child: KoreaCityMapCanvas(
              cities: cities,
              colorByCityId: const {},
              selectedCityId: null,
              labelScaleFactor: 1,
              onTapCity: (city) {
                tapCount++;
                tappedCity = city;
              },
            ),
          ),
        ),
      ),
    );
    for (var i = 0;
        i < 20 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final mapTopLeft = tester.getTopLeft(find.byKey(mapKey));
    final suwonPoint = projectKoreaLocationToCanvas(
      size: const Size(360, 520),
      cities: cities,
      latitude: 37.2636,
      longitude: 127.0286,
    );
    await tester.tapAt(mapTopLeft + suwonPoint);
    await tester.pump();

    expect(tapCount, 1);
    expect(tappedCity, same(suwon));

    final hwaseongPoint = projectKoreaLocationToCanvas(
      size: const Size(360, 520),
      cities: cities,
      latitude: 37.1996,
      longitude: 126.8312,
    );
    await tester.tapAt(mapTopLeft + hwaseongPoint);
    await tester.pump();

    expect(tapCount, 2);
    expect(tappedCity, same(hwaseong));

    final pyeongtaekPoint = projectKoreaLocationToCanvas(
      size: const Size(360, 520),
      cities: cities,
      latitude: 36.9921,
      longitude: 127.1129,
    );
    await tester.tapAt(mapTopLeft + pyeongtaekPoint);
    await tester.pump();

    expect(tapCount, 2, reason: '목록에 없는 평택시가 가까운 도시로 선택되면 안 됨');
  });
}

void _visitCoordinates(
  dynamic value,
  void Function(double longitude, double latitude) visitor,
) {
  if (value is! List<dynamic> || value.isEmpty) return;
  if (value.length >= 2 && value[0] is num && value[1] is num) {
    visitor((value[0] as num).toDouble(), (value[1] as num).toDouble());
    return;
  }
  for (final child in value) {
    _visitCoordinates(child, visitor);
  }
}

List<TravelCity> _allTravelCities() {
  return [
    ..._seedCitiesFromMigration(
      'supabase/migrations/202607110000_dear_baseline.sql',
    ),
    ..._seedCitiesFromMigration(
      'supabase/migrations/202607140002_expand_domestic_travel_regions.sql',
    ),
  ];
}

List<TravelCity> _seedCitiesFromMigration(String path) {
  final sql = File(path).readAsStringSync();
  final sectionStart = sql.indexOf(
    'from (values',
    sql.indexOf('insert into public.travel_cities'),
  );
  if (sectionStart < 0) {
    throw StateError('travel_cities values seed not found: $path');
  }
  final sectionEnd = sql.indexOf(') as seed', sectionStart);
  final section = sql.substring(sectionStart, sectionEnd);
  final rowPattern = RegExp(
    r"\('([^']+)', '([^']+)', '([^']*)', ([\d.]+), ([\d.]+), (\d+)\)",
  );

  return [
    for (final match in rowPattern.allMatches(section))
      TravelCity(
        id: match.group(1)!,
        code: match.group(1)!,
        name: match.group(2)!,
        regionGroup: match.group(3)!,
        centerLat: double.parse(match.group(4)!),
        centerLng: double.parse(match.group(5)!),
        sortOrder: int.parse(match.group(6)!),
      ),
  ];
}

TravelCity _city({required String code, required String name}) {
  return TravelCity(
    id: code,
    code: code,
    name: name,
    regionGroup: '테스트',
    centerLat: 36.5,
    centerLng: 127.5,
    sortOrder: 0,
  );
}

void _expectValidPolygon(dynamic rawPolygon, {required String reason}) {
  expect(rawPolygon, isA<List<dynamic>>(), reason: reason);
  final polygon = rawPolygon as List<dynamic>;
  expect(polygon, isNotEmpty, reason: reason);

  for (final rawRing in polygon) {
    expect(rawRing, isA<List<dynamic>>(), reason: reason);
    final ring = rawRing as List<dynamic>;
    expect(ring.length, greaterThanOrEqualTo(4), reason: reason);

    for (final rawPoint in ring) {
      expect(rawPoint, isA<List<dynamic>>(), reason: reason);
      final point = rawPoint as List<dynamic>;
      expect(point.length, greaterThanOrEqualTo(2), reason: reason);
      for (final ordinate in point) {
        expect(ordinate, isA<num>(), reason: reason);
        expect((ordinate as num).toDouble().isFinite, isTrue, reason: reason);
      }
    }

    expect(ring.last, orderedEquals(ring.first), reason: reason);
  }
}
