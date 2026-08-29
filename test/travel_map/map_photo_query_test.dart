import 'dart:io';

import 'package:couple_chat_app/src/features/travel_map/data/map_photo_query.dart';
import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('사진 realtime scope는 커플과 장소를 한 서버 필터로 결합한다', () {
    final scope = mapPhotoQueryScope(
      coupleId: 'couple-1',
      placeId: 'place-1',
    );

    expect(MapPhotoQueryScope.column, 'realtime_scope');
    expect(scope.value, 'couple-1:place-1');
    expect(scope.limit, mapPhotoHeadLimit);
    expect(mapPhotoHeadLimit, 12);
  });

  test('사진 scope는 범위 없는 커플 또는 장소를 거부한다', () {
    expect(
      () => mapPhotoQueryScope(coupleId: '', placeId: 'place-1'),
      throwsArgumentError,
    );
    expect(
      () => mapPhotoQueryScope(coupleId: 'couple-1', placeId: '  '),
      throwsArgumentError,
    );
  });

  test('signed URL은 유효 시간 동안 snapshot 사이에서 재사용한다', () async {
    var now = DateTime(2026, 7, 12, 10);
    var signCalls = 0;
    final cache = MapPhotoSignedUrlCache(
      clock: () => now,
      signer: (path) async => 'signed-${++signCalls}-$path',
    );

    expect(await cache.resolve('photo.jpg'), 'signed-1-photo.jpg');
    now = now.add(const Duration(minutes: 40));
    expect(await cache.resolve('photo.jpg'), 'signed-1-photo.jpg');
    expect(signCalls, 1);

    now = now.add(const Duration(minutes: 16));
    expect(await cache.resolve('photo.jpg'), 'signed-2-photo.jpg');
    expect(signCalls, 2);
  });

  test('한 사진의 signed URL 실패가 정상 사진을 숨기지 않는다', () async {
    var failures = 0;
    final photos = await resolveTravelCityPhotoRows(
      [
        _photoRow(id: 'photo-1', storagePath: 'ok.jpg'),
        _photoRow(id: 'photo-2', storagePath: 'broken.jpg'),
      ],
      signer: (path) async {
        if (path == 'broken.jpg') throw Exception('sign failed');
        return 'signed-$path';
      },
      onSignFailure: (_, __) => failures++,
    );

    expect(photos, hasLength(2));
    expect(photos.first.signedUrl, 'signed-ok.jpg');
    expect(photos.last.signedUrl, isNull);
    expect(failures, 1);
  });

  test('migration은 장소별 scope, bounded index, 공동 삭제 정책을 고정한다', () async {
    final sql = await File(
      'supabase/migrations/202607120010_map_photo_scope_and_shared_delete.sql',
    ).readAsString();

    expect(sql, contains('generated always as'));
    expect(sql, contains('realtime_scope, created_at desc'));
    expect(sql, contains('replica identity full'));
    expect(sql, contains('travel_city_photos_delete_couple'));
    expect(sql, contains('world_country_photos_delete_couple'));
    expect(sql, contains('travel_city_photo_objects_delete_couple'));
    expect(sql, isNot(contains('owner_id = auth.uid()')));
  });
}

Map<String, dynamic> _photoRow({
  required String id,
  required String storagePath,
}) {
  return {
    'id': id,
    'couple_id': 'couple-1',
    'city_id': 'city-1',
    'storage_path': storagePath,
    'caption': null,
    'uploaded_by': 'user-1',
    'created_at': '2026-08-30T00:00:00Z',
  };
}
