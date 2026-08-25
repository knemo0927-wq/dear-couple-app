import 'dart:async';
import 'dart:io';

import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  MemoryAlbum album({
    required String id,
    required DateTime updatedAt,
    bool isFeatured = false,
    int photoCount = 0,
  }) {
    return MemoryAlbum(
      id: id,
      coupleId: 'couple-1',
      name: 'album-$id',
      createdBy: 'user-1',
      createdAt: updatedAt.subtract(const Duration(days: 1)),
      updatedAt: updatedAt,
      isFeatured: isFeatured,
      photoCount: photoCount,
    );
  }

  MemoryAlbumPhoto photo({
    required String id,
    required DateTime createdAt,
  }) {
    return MemoryAlbumPhoto(
      id: id,
      albumId: 'album-1',
      coupleId: 'couple-1',
      storagePath: '$id.jpg',
      uploadedBy: 'user-1',
      createdAt: createdAt,
    );
  }

  MemoryAlbumPhotoDeletion deletion(String photoId) {
    return MemoryAlbumPhotoDeletion(
      eventId: 1,
      photoId: photoId,
      albumId: 'album-1',
      coupleId: 'couple-1',
      deletedAt: DateTime.utc(2026, 7, 12),
    );
  }

  test('album page는 featured/updated/id 순서를 유지하고 cursor를 만든다', () {
    final page = memoryAlbumPageFromRows(
      [
        album(id: 'b', updatedAt: DateTime.utc(2026, 7, 10)),
        album(
          id: 'featured',
          updatedAt: DateTime.utc(2026, 7, 1),
          isFeatured: true,
        ),
        album(id: 'a', updatedAt: DateTime.utc(2026, 7, 10)),
      ],
      pageSize: 2,
    );

    expect(page.items.map((item) => item.id), ['featured', 'b']);
    expect(page.hasMore, isTrue);
    expect(
      page.nextCursor,
      const TypeMatcher<MemoryAlbumCursor>(),
    );
    expect(page.nextCursor?.id, 'b');
    expect(page.nextCursor?.isFeatured, isFalse);
  });

  test('album feed는 다음 cursor page를 명시적으로 합친다', () async {
    final first = album(id: 'new', updatedAt: DateTime.utc(2026, 7, 12));
    final second = album(id: 'middle', updatedAt: DateTime.utc(2026, 7, 11));
    final older = album(id: 'older', updatedAt: DateTime.utc(2026, 7, 10));
    final repository = _FeedRepository(
      fetchAlbumPage: ({cursor}) async {
        if (cursor == null) {
          return MemoryAlbumListPage(
            items: [first, second],
            nextCursor: MemoryAlbumCursor(
              isFeatured: second.isFeatured,
              updatedAt: second.updatedAt,
              id: second.id,
            ),
            hasMore: true,
          );
        }
        return MemoryAlbumListPage(
          items: [older],
          nextCursor: MemoryAlbumCursor(
            isFeatured: older.isFeatured,
            updatedAt: older.updatedAt,
            id: older.id,
          ),
          hasMore: false,
        );
      },
    );
    final controller = MemoryAlbumFeedController(
      repository: repository,
      coupleId: 'couple-1',
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });

    await _flushAsyncWork();
    expect(controller.state.items.map((item) => item.id), ['new', 'middle']);
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();

    expect(
      controller.state.items.map((item) => item.id),
      ['new', 'middle', 'older'],
    );
    expect(controller.state.hasMore, isFalse);
    expect(repository.albumPageCalls, 2);
  });

  test('필터 cursor의 과거 사진도 외부 deletion event 즉시 제거한다', () async {
    final recent = photo(id: 'recent', createdAt: DateTime.utc(2026, 7, 12));
    final older = photo(id: 'older', createdAt: DateTime.utc(2026, 6, 1));
    final repository = _FeedRepository(
      fetchPhotoPage: () async => MemoryAlbumPhotoPage(
        items: [recent, older],
        nextCursor: MemoryAlbumPhotoCursor(
          createdAt: older.createdAt,
          id: older.id,
        ),
        hasMore: false,
      ),
    );
    final controller = MemoryAlbumPhotoFeedController(
      repository: repository,
      args: const MemoryAlbumPhotoFeedArgs(
        coupleId: 'couple-1',
        albumId: 'album-1',
        uploadedBy: 'user-1',
      ),
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });
    await _flushAsyncWork();
    expect(controller.state.items.map((item) => item.id), ['recent', 'older']);

    repository.deletionEvents.add([deletion('older')]);
    await _flushAsyncWork();

    expect(controller.state.items.map((item) => item.id), ['recent']);
  });

  test('DELETE와 cursor fetch 경합에서도 tombstone이 stale 사진 재삽입을 막는다', () async {
    final stale = photo(id: 'stale', createdAt: DateTime.utc(2026, 6, 1));
    final fetchCompleter = Completer<MemoryAlbumPhotoPage>();
    final repository = _FeedRepository(
      fetchPhotoPage: () => fetchCompleter.future,
    );
    final controller = MemoryAlbumPhotoFeedController(
      repository: repository,
      args: const MemoryAlbumPhotoFeedArgs(
        coupleId: 'couple-1',
        albumId: 'album-1',
        uploadedBy: 'user-1',
      ),
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });

    repository.deletionEvents.add([deletion('stale')]);
    await _flushAsyncWork();
    fetchCompleter.complete(
      MemoryAlbumPhotoPage(
        items: [stale],
        nextCursor: MemoryAlbumPhotoCursor(
          createdAt: stale.createdAt,
          id: stale.id,
        ),
        hasMore: false,
      ),
    );
    await _flushAsyncWork();

    expect(controller.state.items, isEmpty);
  });

  test('011 migration은 aggregate RPC와 couple-scoped deletion outbox를 정의한다', () {
    final sql = File(
      'supabase/migrations/'
      '202607120011_memory_album_bounded_feed.sql',
    ).readAsStringSync();
    final repository = File(
      'lib/src/features/chat/data/memory_album_repository.dart',
    ).readAsStringSync();

    expect(sql, contains('get_memory_album_page'));
    expect(sql, contains('get_memory_album_summaries'));
    expect(sql, contains('memory_album_photo_deletions_select_couple'));
    expect(sql, contains('memory_album_photos_propagate_delete'));
    expect(repository, isNot(contains('CountOption.exact')));
    expect(repository, contains('.limit(limit)'));
  });
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

typedef _FetchAlbumPage = Future<MemoryAlbumListPage> Function({
  MemoryAlbumCursor? cursor,
});

typedef _FetchPhotoPage = Future<MemoryAlbumPhotoPage> Function();

class _FeedRepository extends MemoryAlbumRepository {
  _FeedRepository({
    _FetchAlbumPage? fetchAlbumPage,
    _FetchPhotoPage? fetchPhotoPage,
  })  : _fetchAlbumPage = fetchAlbumPage,
        _fetchPhotoPage = fetchPhotoPage,
        super(
          client: SupabaseClient(
            'http://localhost:54321',
            'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final _FetchAlbumPage? _fetchAlbumPage;
  final _FetchPhotoPage? _fetchPhotoPage;
  final StreamController<MemoryAlbumHeadSnapshot> albumHead =
      StreamController<MemoryAlbumHeadSnapshot>.broadcast();
  final StreamController<MemoryAlbumPhotoHeadSnapshot> photoHead =
      StreamController<MemoryAlbumPhotoHeadSnapshot>.broadcast();
  final StreamController<List<MemoryAlbumPhotoDeletion>> deletionEvents =
      StreamController<List<MemoryAlbumPhotoDeletion>>.broadcast();
  int albumPageCalls = 0;

  @override
  Stream<MemoryAlbumHeadSnapshot> watchAlbumHead({
    required String coupleId,
    int limit = memoryAlbumPageSize,
  }) {
    return albumHead.stream;
  }

  @override
  Future<MemoryAlbumListPage> fetchAlbumPage({
    required String coupleId,
    MemoryAlbumCursor? cursor,
    int pageSize = memoryAlbumPageSize,
  }) {
    albumPageCalls++;
    final callback = _fetchAlbumPage;
    if (callback == null) {
      return Future.value(
        const MemoryAlbumListPage(
          items: [],
          nextCursor: null,
          hasMore: false,
        ),
      );
    }
    return callback(cursor: cursor);
  }

  @override
  Stream<MemoryAlbumPhotoHeadSnapshot> watchPhotoHeadWindow({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) {
    return photoHead.stream;
  }

  @override
  Stream<List<MemoryAlbumPhotoDeletion>> watchPhotoDeletions({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumDeletionEventWindow,
  }) {
    return deletionEvents.stream;
  }

  @override
  Future<MemoryAlbumPhotoPage> fetchPhotoPage({
    required String coupleId,
    String? albumId,
    MemoryAlbumPhotoCursor? cursor,
    int pageSize = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) {
    final callback = _fetchPhotoPage;
    if (callback == null) {
      return Future.value(
        const MemoryAlbumPhotoPage(
          items: [],
          nextCursor: null,
          hasMore: false,
        ),
      );
    }
    return callback();
  }

  Future<void> close() async {
    await albumHead.close();
    await photoHead.close();
    await deletionEvents.close();
  }
}
