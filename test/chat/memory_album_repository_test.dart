import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MemoryAlbumPhoto photo({
    required String id,
    required DateTime createdAt,
    String? storagePath,
  }) {
    return MemoryAlbumPhoto(
      id: id,
      albumId: 'album-1',
      coupleId: 'couple-1',
      storagePath: storagePath ?? '$id.jpg',
      uploadedBy: 'user-1',
      createdAt: createdAt,
    );
  }

  group('mergeMemoryAlbumPhotos', () {
    test('realtime head와 cursor page를 ID 기준으로 중복 제거한다', () {
      final older = DateTime.utc(2026, 7, 10);
      final newer = DateTime.utc(2026, 7, 12);
      final existing = [
        photo(id: 'a', createdAt: newer, storagePath: 'old-a.jpg'),
        photo(id: 'b', createdAt: older),
      ];
      final incoming = [
        photo(id: 'a', createdAt: newer, storagePath: 'new-a.jpg'),
        photo(id: 'c', createdAt: newer),
      ];

      final merged = mergeMemoryAlbumPhotos(existing, incoming);

      expect(merged.map((item) => item.id), ['c', 'a', 'b']);
      expect(merged.where((item) => item.id == 'a').single.storagePath,
          'new-a.jpg');
    });

    test('같은 생성 시각은 ID 역순으로 안정 정렬한다', () {
      final createdAt = DateTime.utc(2026, 7, 12);

      final merged = mergeMemoryAlbumPhotos(const [], [
        photo(id: 'a', createdAt: createdAt),
        photo(id: 'c', createdAt: createdAt),
        photo(id: 'b', createdAt: createdAt),
      ]);

      expect(merged.map((item) => item.id), ['c', 'b', 'a']);
    });
  });

  group('memoryAlbumPhotoPageFromRows', () {
    test('30장을 노출하고 마지막 항목으로 다음 cursor를 만든다', () {
      final rows = List.generate(
        31,
        (index) => photo(
          id: index.toString().padLeft(2, '0'),
          createdAt: DateTime.utc(2026, 7, 31 - index),
        ),
      );

      final page = memoryAlbumPhotoPageFromRows(rows);

      expect(page.items, hasLength(memoryAlbumPhotoPageSize));
      expect(page.hasMore, isTrue);
      expect(page.nextCursor?.id, page.items.last.id);
      expect(page.nextCursor?.createdAt, page.items.last.createdAt);
    });

    test('중복 행은 page 크기와 hasMore 계산에서 한 번만 센다', () {
      final createdAt = DateTime.utc(2026, 7, 12);
      final duplicate = photo(id: 'same', createdAt: createdAt);

      final page = memoryAlbumPhotoPageFromRows(
        [duplicate, duplicate],
        pageSize: 1,
      );

      expect(page.items, hasLength(1));
      expect(page.hasMore, isFalse);
    });
  });

  group('filterMemoryAlbumPhotos', () {
    test('날짜 범위는 시작 포함·종료 제외이고 업로더를 함께 적용한다', () {
      final photos = [
        photo(id: 'before', createdAt: DateTime.utc(2026, 7, 9)),
        photo(id: 'mine', createdAt: DateTime.utc(2026, 7, 10)),
        MemoryAlbumPhoto(
          id: 'partner',
          albumId: 'album-1',
          coupleId: 'couple-1',
          storagePath: 'partner.jpg',
          uploadedBy: 'user-2',
          createdAt: DateTime.utc(2026, 7, 11),
        ),
        photo(id: 'end', createdAt: DateTime.utc(2026, 7, 12)),
      ];

      final mine = filterMemoryAlbumPhotos(
        photos,
        createdAtOrAfter: DateTime.utc(2026, 7, 10),
        createdAtBefore: DateTime.utc(2026, 7, 12),
        uploadedBy: 'user-1',
      );
      final partner = filterMemoryAlbumPhotos(
        photos,
        createdAtOrAfter: DateTime.utc(2026, 7, 10),
        createdAtBefore: DateTime.utc(2026, 7, 12),
        excludedUploader: 'user-1',
      );

      expect(mine.map((item) => item.id), ['mine']);
      expect(partner.map((item) => item.id), ['partner']);
    });
  });

  group('reconcileMemoryAlbumPhotoHead', () {
    test('30장 미만 realtime snapshot에서 삭제된 사진을 stale로 남기지 않는다', () {
      final current = [
        photo(id: 'deleted', createdAt: DateTime.utc(2026, 7, 12)),
        photo(id: 'kept', createdAt: DateTime.utc(2026, 7, 11)),
      ];

      final reconciled = reconcileMemoryAlbumPhotoHead(
        current,
        [current.last],
      );

      expect(reconciled.map((item) => item.id), ['kept']);
    });

    test('가득 찬 realtime head는 cursor로 불러온 더 오래된 사진을 유지한다', () {
      final head = List.generate(
        memoryAlbumPhotoPageSize,
        (index) => photo(
          id: 'head-${index.toString().padLeft(2, '0')}',
          createdAt: DateTime.utc(2026, 7, 31).subtract(Duration(days: index)),
        ),
      );
      final older = photo(id: 'older', createdAt: DateTime.utc(2026, 6, 1));

      final reconciled = reconcileMemoryAlbumPhotoHead(
        [...head, older],
        head,
      );

      expect(reconciled, hasLength(memoryAlbumPhotoPageSize + 1));
      expect(reconciled.last.id, 'older');
    });

    test('필터된 exhaustive head가 비면 외부에서 삭제된 stale 사진도 제거한다', () {
      final current = [
        photo(id: 'mine-deleted', createdAt: DateTime.utc(2026, 7, 12)),
      ];

      final reconciled = reconcileMemoryAlbumPhotoHeadWindow(
        current,
        const MemoryAlbumPhotoHeadSnapshot(
          items: [],
          oldestUnfiltered: null,
          isExhaustive: true,
        ),
      );

      expect(reconciled, isEmpty);
    });

    test('필터된 head 경계보다 오래된 cursor 항목은 유지한다', () {
      final boundary = photo(
        id: 'unfiltered-boundary',
        createdAt: DateTime.utc(2026, 7, 10),
      );
      final filteredHead = photo(
        id: 'filtered-kept',
        createdAt: DateTime.utc(2026, 7, 12),
      );
      final older = photo(id: 'older', createdAt: DateTime.utc(2026, 7, 1));
      final deleted = photo(
        id: 'filtered-deleted',
        createdAt: DateTime.utc(2026, 7, 11),
      );

      final reconciled = reconcileMemoryAlbumPhotoHeadWindow(
        [filteredHead, deleted, older],
        MemoryAlbumPhotoHeadSnapshot(
          items: [filteredHead],
          oldestUnfiltered: boundary,
          isExhaustive: false,
        ),
      );

      expect(reconciled.map((item) => item.id), ['filtered-kept', 'older']);
    });
  });
}
