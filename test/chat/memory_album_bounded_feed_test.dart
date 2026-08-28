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

  test('album refresh는 기존 page를 보존하고 실패 종류를 refresh로 기록한다', () async {
    final current = album(id: 'current', updatedAt: DateTime.utc(2026, 7, 12));
    final pageCursor = MemoryAlbumCursor(
      isFeatured: current.isFeatured,
      updatedAt: current.updatedAt,
      id: current.id,
    );
    final refreshCompleter = Completer<MemoryAlbumListPage>();
    var callCount = 0;
    final repository = _FeedRepository(
      fetchAlbumPage: ({cursor}) {
        callCount++;
        if (callCount == 1) {
          return Future.value(
            MemoryAlbumListPage(
              items: [current, current],
              nextCursor: pageCursor,
              hasMore: true,
            ),
          );
        }
        return refreshCompleter.future;
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
    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(controller.state.nextCursor, pageCursor);
    expect(controller.state.hasLoadedOnce, isTrue);

    final refresh = controller.refresh();
    await _flushAsyncWork();
    expect(controller.state.isRefreshing, isTrue);
    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(controller.state.nextCursor, pageCursor);
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();
    expect(repository.albumPageCalls, 2);

    refreshCompleter.completeError(StateError('refresh failed'));
    await refresh;

    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(controller.state.nextCursor, pageCursor);
    expect(controller.state.hasMore, isTrue);
    expect(controller.state.hasLoadedOnce, isTrue);
    expect(controller.state.isRefreshing, isFalse);
    expect(
      controller.state.failureKind,
      MemoryAlbumFeedFailureKind.refresh,
    );
  });

  test('album feed는 성공한 빈 응답도 최초 load 완료로 기록한다', () async {
    final repository = _FeedRepository();
    final controller = MemoryAlbumFeedController(
      repository: repository,
      coupleId: 'couple-1',
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });

    await _flushAsyncWork();

    expect(controller.state.items, isEmpty);
    expect(controller.state.hasLoadedOnce, isTrue);
    expect(controller.state.isLoadingInitial, isFalse);
    expect(controller.state.isRefreshing, isFalse);
    expect(controller.state.hasMore, isFalse);
    expect(controller.state.error, isNull);
    expect(controller.state.failureKind, isNull);
  });

  test('album loadMore 실패 retry는 refresh 대신 보존한 cursor를 재사용한다', () async {
    final newest = album(id: 'newest', updatedAt: DateTime.utc(2026, 7, 12));
    final older = album(id: 'older', updatedAt: DateTime.utc(2026, 7, 11));
    final pageCursor = MemoryAlbumCursor(
      isFeatured: newest.isFeatured,
      updatedAt: newest.updatedAt,
      id: newest.id,
    );
    final requestedCursors = <MemoryAlbumCursor?>[];
    var loadMoreAttempts = 0;
    final repository = _FeedRepository(
      fetchAlbumPage: ({cursor}) async {
        requestedCursors.add(cursor);
        if (cursor == null) {
          return MemoryAlbumListPage(
            items: [newest, newest],
            nextCursor: pageCursor,
            hasMore: true,
          );
        }
        loadMoreAttempts++;
        if (loadMoreAttempts == 1) {
          throw StateError('load more failed');
        }
        return MemoryAlbumListPage(
          items: [newest, older, older],
          nextCursor: null,
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

    await controller.loadMore();
    expect(controller.state.nextCursor, pageCursor);
    expect(controller.state.hasMore, isTrue);
    expect(
      controller.state.failureKind,
      MemoryAlbumFeedFailureKind.loadMore,
    );

    await controller.retry();

    expect(requestedCursors, [null, pageCursor, pageCursor]);
    expect(controller.state.items.map((item) => item.id), ['newest', 'older']);
    expect(controller.state.hasMore, isFalse);
    expect(controller.state.error, isNull);
    expect(controller.state.failureKind, isNull);
  });

  test('album realtime 실패는 기존 항목을 보존하고 다음 snapshot에서 해제한다', () async {
    final current = album(id: 'current', updatedAt: DateTime.utc(2026, 7, 12));
    final repository = _FeedRepository(
      fetchAlbumPage: ({cursor}) async => MemoryAlbumListPage(
        items: [current],
        nextCursor: null,
        hasMore: false,
      ),
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

    repository.albumHead.addError(StateError('realtime failed'));
    await _flushAsyncWork();

    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(
      controller.state.failureKind,
      MemoryAlbumFeedFailureKind.realtime,
    );

    repository.albumHead.add(
      MemoryAlbumHeadSnapshot(
        items: [current, current],
        oldest: current,
        isExhaustive: true,
      ),
    );
    await _flushAsyncWork();

    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(controller.state.error, isNull);
    expect(controller.state.failureKind, isNull);
  });

  test('필터 cursor의 과거 사진도 외부 deletion event 즉시 제거한다', () async {
    final recent = photo(id: 'recent', createdAt: DateTime.utc(2026, 7, 12));
    final older = photo(id: 'older', createdAt: DateTime.utc(2026, 6, 1));
    final repository = _FeedRepository(
      fetchPhotoPage: ({cursor}) async => MemoryAlbumPhotoPage(
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
      fetchPhotoPage: ({cursor}) => fetchCompleter.future,
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

  test('photo refresh는 기존 page를 보존하고 실패 종류를 refresh로 기록한다', () async {
    final current = photo(id: 'current', createdAt: DateTime.utc(2026, 7, 12));
    final pageCursor = MemoryAlbumPhotoCursor(
      createdAt: current.createdAt,
      id: current.id,
    );
    final refreshCompleter = Completer<MemoryAlbumPhotoPage>();
    var callCount = 0;
    final repository = _FeedRepository(
      fetchPhotoPage: ({cursor}) {
        callCount++;
        if (callCount == 1) {
          return Future.value(
            MemoryAlbumPhotoPage(
              items: [current, current],
              nextCursor: pageCursor,
              hasMore: true,
            ),
          );
        }
        return refreshCompleter.future;
      },
    );
    final controller = MemoryAlbumPhotoFeedController(
      repository: repository,
      args: const MemoryAlbumPhotoFeedArgs(
        coupleId: 'couple-1',
        albumId: 'album-1',
      ),
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });

    await _flushAsyncWork();
    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(controller.state.nextCursor, pageCursor);
    expect(controller.state.hasLoadedOnce, isTrue);

    final refresh = controller.refresh();
    await _flushAsyncWork();
    expect(controller.state.isRefreshing, isTrue);
    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(controller.state.nextCursor, pageCursor);
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();
    expect(repository.photoPageCalls, 2);

    refreshCompleter.completeError(StateError('refresh failed'));
    await refresh;

    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(controller.state.nextCursor, pageCursor);
    expect(controller.state.hasMore, isTrue);
    expect(controller.state.hasLoadedOnce, isTrue);
    expect(controller.state.isRefreshing, isFalse);
    expect(
      controller.state.failureKind,
      MemoryAlbumFeedFailureKind.refresh,
    );
  });

  test('photo feed는 성공한 빈 응답도 최초 load 완료로 기록한다', () async {
    final repository = _FeedRepository();
    final controller = MemoryAlbumPhotoFeedController(
      repository: repository,
      args: const MemoryAlbumPhotoFeedArgs(
        coupleId: 'couple-1',
        albumId: 'album-1',
      ),
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });

    await _flushAsyncWork();

    expect(controller.state.items, isEmpty);
    expect(controller.state.hasLoadedOnce, isTrue);
    expect(controller.state.isLoadingInitial, isFalse);
    expect(controller.state.isRefreshing, isFalse);
    expect(controller.state.hasMore, isFalse);
    expect(controller.state.error, isNull);
    expect(controller.state.failureKind, isNull);
  });

  test('photo loadMore 실패 retry는 refresh 대신 보존한 cursor를 재사용한다', () async {
    final newest = photo(id: 'newest', createdAt: DateTime.utc(2026, 7, 12));
    final older = photo(id: 'older', createdAt: DateTime.utc(2026, 7, 11));
    final pageCursor = MemoryAlbumPhotoCursor(
      createdAt: newest.createdAt,
      id: newest.id,
    );
    final requestedCursors = <MemoryAlbumPhotoCursor?>[];
    var loadMoreAttempts = 0;
    final repository = _FeedRepository(
      fetchPhotoPage: ({cursor}) async {
        requestedCursors.add(cursor);
        if (cursor == null) {
          return MemoryAlbumPhotoPage(
            items: [newest, newest],
            nextCursor: pageCursor,
            hasMore: true,
          );
        }
        loadMoreAttempts++;
        if (loadMoreAttempts == 1) {
          throw StateError('load more failed');
        }
        return MemoryAlbumPhotoPage(
          items: [newest, older, older],
          nextCursor: null,
          hasMore: false,
        );
      },
    );
    final controller = MemoryAlbumPhotoFeedController(
      repository: repository,
      args: const MemoryAlbumPhotoFeedArgs(
        coupleId: 'couple-1',
        albumId: 'album-1',
      ),
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });
    await _flushAsyncWork();

    await controller.loadMore();
    expect(controller.state.nextCursor, pageCursor);
    expect(controller.state.hasMore, isTrue);
    expect(
      controller.state.failureKind,
      MemoryAlbumFeedFailureKind.loadMore,
    );

    await controller.retry();

    expect(requestedCursors, [null, pageCursor, pageCursor]);
    expect(controller.state.items.map((item) => item.id), ['newest', 'older']);
    expect(controller.state.hasMore, isFalse);
    expect(controller.state.error, isNull);
    expect(controller.state.failureKind, isNull);
  });

  test('photo realtime 실패는 기존 항목을 보존하고 다음 snapshot에서 해제한다', () async {
    final current = photo(id: 'current', createdAt: DateTime.utc(2026, 7, 12));
    final repository = _FeedRepository(
      fetchPhotoPage: ({cursor}) async => MemoryAlbumPhotoPage(
        items: [current],
        nextCursor: null,
        hasMore: false,
      ),
    );
    final controller = MemoryAlbumPhotoFeedController(
      repository: repository,
      args: const MemoryAlbumPhotoFeedArgs(
        coupleId: 'couple-1',
        albumId: 'album-1',
      ),
    );
    addTearDown(() async {
      controller.dispose();
      await repository.close();
    });
    await _flushAsyncWork();

    repository.photoHead.addError(StateError('realtime failed'));
    await _flushAsyncWork();

    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(
      controller.state.failureKind,
      MemoryAlbumFeedFailureKind.realtime,
    );

    repository.photoHead.add(
      MemoryAlbumPhotoHeadSnapshot(
        items: [current, current],
        oldestUnfiltered: current,
        isExhaustive: true,
      ),
    );
    await _flushAsyncWork();

    expect(controller.state.items.map((item) => item.id), ['current']);
    expect(controller.state.error, isNull);
    expect(controller.state.failureKind, isNull);
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

typedef _FetchPhotoPage = Future<MemoryAlbumPhotoPage> Function({
  MemoryAlbumPhotoCursor? cursor,
});

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
  int photoPageCalls = 0;

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
    photoPageCalls++;
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
    return callback(cursor: cursor);
  }

  Future<void> close() async {
    await albumHead.close();
    await photoHead.close();
    await deletionEvents.close();
  }
}
