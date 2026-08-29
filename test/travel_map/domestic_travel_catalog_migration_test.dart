import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrationPath = 'supabase/migrations/'
    '202608300001_reconcile_domestic_travel_regions.sql';

void main() {
  late String migration;
  late List<_CatalogRow> canonicalRows;

  setUpAll(() {
    migration = File(_migrationPath).readAsStringSync();
    canonicalRows = _parseCanonicalRows(migration);
  });

  test('복구 카탈로그는 기존 두 seed와 같은 161개 canonical 값을 가진다', () {
    final previousRows = <_CatalogRow>[
      ..._parseLegacyRows(
        'supabase/migrations/202607110000_dear_baseline.sql',
      ),
      ..._parseLegacyRows(
        'supabase/migrations/202607140002_expand_domestic_travel_regions.sql',
      ),
    ]..sort(_compareRows);
    final repairedRows = [...canonicalRows]..sort(_compareRows);

    expect(repairedRows, hasLength(161));
    expect(
      repairedRows.map((row) => row.code).toSet(),
      hasLength(161),
    );
    expect(
      repairedRows.map((row) => row.sortOrder),
      orderedEquals(List<int>.generate(161, (index) => index + 1)),
    );
    expect(
      repairedRows.map((row) => row.signature),
      orderedEquals(previousRows.map((row) => row.signature)),
    );
  });

  test('광명은 경기 canonical 코드와 메타데이터로 복구된다', () {
    final gwangmyeong = canonicalRows.singleWhere(
      (row) => row.code == 'SIG_31060',
    );

    expect(gwangmyeong.name, '광명');
    expect(gwangmyeong.regionGroup, '경기');
    expect(gwangmyeong.centerLat, 37.445087);
    expect(gwangmyeong.centerLng, 126.864690);
    expect(gwangmyeong.sortOrder, 44);

    final sameNameRows = canonicalRows.where((row) => row.name == '광주');
    expect(
      sameNameRows.map((row) => '${row.code}:${row.regionGroup}').toSet(),
      {'METRO_24:광주', 'SIG_31250:경기'},
    );
  });

  test('code upsert는 기존 id와 참조 테이블을 변경하지 않는다', () {
    final insertMatch = RegExp(
      r'insert into public\.travel_cities\s*\(([\s\S]*?)\)\s*select',
    ).firstMatch(migration);
    expect(insertMatch, isNotNull);
    final insertColumns = insertMatch!.group(1)!;

    final updateMatch = RegExp(
      r'on conflict \(code\) do update\s*set([\s\S]*?);',
    ).firstMatch(migration);
    expect(updateMatch, isNotNull);
    final updateClause = updateMatch!.group(1)!;

    expect(insertColumns, isNot(matches(RegExp(r'\bid\b'))));
    expect(updateClause, isNot(matches(RegExp(r'\bid\s*='))));
    expect(migration, contains('on conflict (code) do update'));
    expect(migration, contains('lock table public.travel_cities'));
    expect(
      migration,
      isNot(matches(RegExp(r'\b(delete|truncate)\b', caseSensitive: false))),
    );
    expect(
      migration,
      isNot(
        matches(
          RegExp(
            r'\b(alter|insert into|update)\s+'
            r'public\.travel_city_(visits|photos)\b',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  test('트랜잭션 안에서 exact code·count·sort·value postcondition을 검증한다', () {
    expect(migration.trimLeft(), startsWith('begin;'));
    expect(migration.trimRight(), endsWith('commit;'));
    expect(migration, contains('on commit drop'));

    for (final contract in [
      'actual_count <> 161',
      'actual_sort_count <> 161',
      'actual_min_sort <> 1',
      'actual_max_sort <> 161',
      'missing_code_count <> 0',
      'unexpected_code_count <> 0',
      'mismatched_value_count <> 0',
      'actual.name is distinct from canonical.name',
      'actual.region_group is distinct from canonical.region_group',
      'actual.center_lat is distinct from canonical.center_lat',
      'actual.center_lng is distinct from canonical.center_lng',
      'actual.sort_order is distinct from canonical.sort_order',
      "errcode = '23514'",
    ]) {
      expect(migration, contains(contract), reason: contract);
    }
  });
}

List<_CatalogRow> _parseCanonicalRows(String sql) {
  final insertStart = sql.indexOf('insert into canonical_travel_cities');
  if (insertStart < 0) {
    throw StateError('canonical travel seed insert not found: $_migrationPath');
  }
  final valuesStart = sql.indexOf('\nvalues\n', insertStart);
  final valuesEnd = sql.indexOf(';\n\ndo \$\$', valuesStart);
  if (valuesStart < 0 || valuesEnd < 0) {
    throw StateError('canonical travel seed values not found: $_migrationPath');
  }
  return _parseRows(sql.substring(valuesStart, valuesEnd));
}

List<_CatalogRow> _parseLegacyRows(String path) {
  final sql = File(path).readAsStringSync();
  final insertStart = sql.indexOf('insert into public.travel_cities');
  final valuesStart = sql.indexOf('from (values', insertStart);
  final valuesEnd = sql.indexOf(') as seed', valuesStart);
  if (insertStart < 0 || valuesStart < 0 || valuesEnd < 0) {
    throw StateError('legacy travel seed values not found: $path');
  }
  return _parseRows(sql.substring(valuesStart, valuesEnd));
}

List<_CatalogRow> _parseRows(String section) {
  final rowPattern = RegExp(
    r"\('([^']+)', '([^']+)', '([^']*)', "
    r'(-?[\d.]+), (-?[\d.]+), (\d+)\)',
  );
  return [
    for (final match in rowPattern.allMatches(section))
      _CatalogRow(
        code: match.group(1)!,
        name: match.group(2)!,
        regionGroup: match.group(3)!,
        centerLat: double.parse(match.group(4)!),
        centerLng: double.parse(match.group(5)!),
        sortOrder: int.parse(match.group(6)!),
      ),
  ];
}

int _compareRows(_CatalogRow left, _CatalogRow right) =>
    left.sortOrder.compareTo(right.sortOrder);

class _CatalogRow {
  const _CatalogRow({
    required this.code,
    required this.name,
    required this.regionGroup,
    required this.centerLat,
    required this.centerLng,
    required this.sortOrder,
  });

  final String code;
  final String name;
  final String regionGroup;
  final double centerLat;
  final double centerLng;
  final int sortOrder;

  String get signature =>
      '$code|$name|$regionGroup|$centerLat|$centerLng|$sortOrder';
}
