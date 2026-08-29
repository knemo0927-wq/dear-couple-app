import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('국내 사진 scope 복구 migration은 선택적 세계지도 schema에 의존하지 않는다', () async {
    final sql = await File(
      'supabase/migrations/'
      '202608300002_repair_travel_city_photo_realtime_scope.sql',
    ).readAsString();

    expect(sql, contains("to_regclass('public.travel_city_photos')"));
    expect(sql, contains('generated always as'));
    expect(sql, contains('travel_city_photos_realtime_head_idx'));
    expect(sql, contains('replica identity full'));
    expect(sql, contains('has an unexpected definition'));
    expect(sql, contains("notify pgrst, 'reload schema'"));
    expect(sql, isNot(contains('world_country_photos')));
  });
}
