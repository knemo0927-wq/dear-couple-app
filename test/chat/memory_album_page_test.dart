import 'dart:async';
import 'dart:typed_data';

import 'package:couple_chat_app/src/common/dear_main_tab_nav.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/memory_album_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const coupleId = '11111111-1111-4111-8111-111111111111';
  const profile = ProfileInfo(
    userId: 'user-1',
    nickname: '우리',
    pairingCode: 'ABCD',
    coupleId: coupleId,
    avatarPath: null,
  );
  final album = MemoryAlbum(
    id: 'album-1',
    coupleId: coupleId,
    name: '우리의 여름',
    createdBy: 'user-1',
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 12),
    photoCount: 0,
    isFeatured: true,
  );
  final destinationAlbum = MemoryAlbum(
    id: 'album-2',
    coupleId: coupleId,
    name: '가을 산책',
    createdBy: 'user-2',
    createdAt: DateTime.utc(2026, 7, 2),
    updatedAt: DateTime.utc(2026, 7, 11),
    photoCount: 0,
  );
  final photos = [
    MemoryAlbumPhoto(
      id: 'photo-1',
      albumId: 'album-1',
      coupleId: coupleId,
      storagePath: 'photo-1.jpg',
      uploadedBy: 'user-1',
      createdAt: DateTime.utc(2026, 7, 12),
    ),
    MemoryAlbumPhoto(
      id: 'photo-2',
      albumId: 'album-1',
      coupleId: coupleId,
      storagePath: 'photo-2.jpg',
      uploadedBy: 'user-2',
      createdAt: DateTime.utc(2026, 7, 11),
    ),
  ];

  late GoRouter router;

  Future<void> pumpAlbum(
    WidgetTester tester, {
    List<MemoryAlbum>? albums,
    List<MemoryAlbumPhoto> photos = const [],
    _FakeMemoryAlbumRepository? repository,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    router = GoRouter(
      initialLocation: '/album',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, navigationShell) =>
              DearMainTabShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, __) => const Scaffold(body: Text('home')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/album',
                  builder: (_, __) => const MemoryAlbumPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/more',
                  builder: (_, __) => const Scaffold(body: Text('more')),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          memoryAlbumRepositoryProvider.overrideWithValue(
            repository ??
                _FakeMemoryAlbumRepository(
                  albums: albums ?? [album],
                  photos: photos,
                ),
          ),
          createMemoryAlbumPhotoUrlsProvider.overrideWithValue(
            (paths) async =>
                paths.map((path) => 'https://example.invalid/$path').toList(),
          ),
          ...overrides,
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('루트 앨범은 공통 하단 탭을 중복 생성하지 않고 명세 상단을 표시한다', (tester) async {
    await pumpAlbum(tester);

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('추억 앨범'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-album-button')), findsOneWidget);
    expect(find.byIcon(Icons.people_alt_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  testWidgets('앨범 카드와 행의 점 세 개 메뉴에서 수정·삭제를 찾을 수 있다', (tester) async {
    await pumpAlbum(tester);

    expect(
        find.byKey(const ValueKey('album-card-menu-album-1')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('album-row-menu-album-1')),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('album-row-menu-album-1')));
    await tester.pumpAndSettle();

    expect(find.text('앨범 수정'), findsOneWidget);
    expect(find.text('앨범 삭제'), findsOneWidget);
  });

  testWidgets('전체 앨범 목록은 끝에 가까워지면 다음 30개 cursor page를 불러온다', (tester) async {
    final manyAlbums = List<MemoryAlbum>.generate(
      31,
      (index) => MemoryAlbum(
        id: 'album-${index + 1}',
        coupleId: coupleId,
        name: index == 30 ? '오래된 마지막 앨범' : '앨범 ${index + 1}',
        createdBy: 'user-1',
        createdAt: DateTime.utc(2026, 7, 12).subtract(Duration(days: index)),
        updatedAt: DateTime.utc(2026, 7, 12).subtract(Duration(days: index)),
        isFeatured: index == 0,
      ),
    );
    var pageCalls = 0;
    final repository = _FakeMemoryAlbumRepository(
      albums: manyAlbums,
      onFetchAlbumPage: (cursor) async {
        pageCalls++;
        if (cursor == null) {
          final first = manyAlbums.take(30).toList(growable: false);
          final last = first.last;
          return MemoryAlbumListPage(
            items: first,
            nextCursor: MemoryAlbumCursor(
              isFeatured: last.isFeatured,
              updatedAt: last.updatedAt,
              id: last.id,
            ),
            hasMore: true,
          );
        }
        return MemoryAlbumListPage(
          items: [manyAlbums.last],
          nextCursor: null,
          hasMore: false,
        );
      },
    );
    await pumpAlbum(tester, repository: repository);

    final list = find.byType(ListView);
    for (var index = 0; index < 4 && pageCalls < 2; index++) {
      await tester.fling(list, const Offset(0, -1400), 5000);
      await tester.pumpAndSettle();
    }

    expect(pageCalls, 2);
    expect(find.text('오래된 마지막 앨범'), findsOneWidget);
  });

  testWidgets('최근 추억 전체 보기는 실제 전체 사진 화면을 연다', (tester) async {
    await pumpAlbum(tester);

    await tester.scrollUntilVisible(
      find.text('전체 보기'),
      260,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('전체 보기'));
    await tester.pumpAndSettle();

    expect(find.text('전체 사진'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('앨범 상세는 뒤로가기를 표시하고 공통 하단 탭을 숨긴다', (tester) async {
    await pumpAlbum(tester);

    await tester.tap(find.byKey(const ValueKey('album-cover-card-album-1')));
    await tester.pumpAndSettle();

    expect(find.text('우리의 여름'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('upload-album-photos-button')),
        findsOneWidget);
  });

  testWidgets('다중 사진 업로드 중 진행 상태를 표시한다', (tester) async {
    final upload = Completer<void>();
    await pumpAlbum(
      tester,
      overrides: [
        chatPickImagesProvider.overrideWithValue(() async => [
              PickedChatImage(
                bytes: Uint8List.fromList([1, 2, 3]),
                extension: 'jpg',
              ),
            ]),
        uploadMemoryAlbumPhotoProvider.overrideWithValue(({
          required String coupleId,
          required String albumId,
          required Uint8List bytes,
          required String extension,
        }) {
          return upload.future;
        }),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('album-cover-card-album-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 올리기'));
    await tester.pump();

    expect(find.byKey(const ValueKey('album-upload-status')), findsOneWidget);
    expect(find.text('사진 업로드 중 0/1'), findsOneWidget);

    upload.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('album-upload-status')), findsNothing);
  });

  testWidgets('다중 업로드는 실패 항목만 남겨 성공 사진 중복 없이 재시도한다', (tester) async {
    final attempts = <int>[];
    var firstImageFailures = 0;
    await pumpAlbum(
      tester,
      overrides: [
        chatPickImagesProvider.overrideWithValue(() async => [
              PickedChatImage(
                bytes: Uint8List.fromList([1]),
                extension: 'jpg',
              ),
              PickedChatImage(
                bytes: Uint8List.fromList([2]),
                extension: 'jpg',
              ),
            ]),
        uploadMemoryAlbumPhotoProvider.overrideWithValue(({
          required String coupleId,
          required String albumId,
          required Uint8List bytes,
          required String extension,
        }) async {
          attempts.add(bytes.first);
          if (bytes.first == 1 && firstImageFailures++ == 0) {
            throw StateError('temporary upload failure');
          }
        }),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('album-cover-card-album-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진 올리기'));
    await tester.pumpAndSettle();

    expect(attempts, [1, 2]);
    expect(
      find.byKey(const ValueKey('retry-album-photos-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('retry-album-photos-button')),
    );
    await tester.pumpAndSettle();

    expect(attempts, [1, 2, 1]);
    expect(
      find.byKey(const ValueKey('retry-album-photos-button')),
      findsNothing,
    );
  });

  testWidgets('빈 상태는 첫 앨범 만들기 CTA 하나만 제공한다', (tester) async {
    await pumpAlbum(tester, albums: const []);

    expect(find.text('첫 앨범을 만들어보세요'), findsOneWidget);
    expect(find.text('첫 앨범 만들기'), findsOneWidget);
    expect(find.text('새 앨범 만들기'), findsNothing);
  });

  testWidgets('전체 사진은 날짜와 업로더 필터를 제공하고 결과 없음 상태를 구분한다', (tester) async {
    final repository = _FakeMemoryAlbumRepository(
      albums: [album],
      photos: photos,
    );
    await pumpAlbum(tester, repository: repository);
    await _openAllPhotos(tester);

    expect(find.byKey(const ValueKey('all-photo-date-filter')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('all-photo-uploader-filter')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('all-photo-date-filter')));
    await tester.pumpAndSettle();
    expect(find.text('사진 날짜 필터'), findsOneWidget);
    expect(find.text('직접 날짜 선택'), findsOneWidget);
    await tester.tap(find.text('최근 30일'));
    await tester.pumpAndSettle();
    expect(repository.lastCreatedAtOrAfter, isNotNull);

    await tester.drag(
      find.byKey(const ValueKey('all-photo-filter-scroll')),
      const Offset(-260, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('all-photo-uploader-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('상대가 올린 사진').last);
    await tester.pumpAndSettle();

    expect(repository.lastExcludedUploader, 'user-1');
    expect(find.text('상대가 올린 사진'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('memory-photo-photo-2.jpg')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('memory-photo-photo-1.jpg')), findsNothing);
  });

  testWidgets('다중 선택 삭제는 확인 후 한 번만 실행되고 완료 뒤 목록을 갱신한다', (tester) async {
    final deleteCompleter = Completer<int>();
    var deleteCallCount = 0;
    Iterable<String>? deletedIds;
    final repository = _FakeMemoryAlbumRepository(
      albums: [album],
      photos: photos,
      onDeletePhotos: (receivedCoupleId, photoIds) {
        expect(receivedCoupleId, coupleId);
        deleteCallCount++;
        deletedIds = photoIds.toList();
        return deleteCompleter.future;
      },
    );
    await pumpAlbum(
      tester,
      repository: repository,
    );
    await _openAllPhotos(tester);

    await tester.tap(find.byKey(const ValueKey('start-photo-selection')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('memory-photo-photo-1.jpg')));
    await tester.tap(find.byKey(const ValueKey('memory-photo-photo-2.jpg')));
    await tester.pump();
    expect(find.text('2장 선택'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('delete-selected-memory-photos')),
    );
    await tester.pumpAndSettle();
    expect(find.text('사진 2장을 삭제할까요?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '삭제'),
      ),
    );
    await tester.pump();

    expect(deleteCallCount, 1);
    expect(deletedIds, containsAll(<String>['photo-1', 'photo-2']));
    expect(find.text('처리 중'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('delete-selected-memory-photos')),
          )
          .onPressed,
      isNull,
    );

    deleteCompleter.complete(2);
    await tester.pumpAndSettle();
    expect(deleteCallCount, 1);
    expect(find.text('사진 2장을 삭제했어요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('start-photo-selection')), findsOneWidget);
  });

  testWidgets('필터 결과가 비면 전체 빈 상태와 다른 안내를 표시한다', (tester) async {
    await pumpAlbum(tester, photos: [photos.first]);
    await _openAllPhotos(tester);

    await tester.tap(
      find.byKey(const ValueKey('all-photo-uploader-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('상대가 올린 사진').last);
    await tester.pumpAndSettle();

    expect(find.text('조건에 맞는 사진이 없어요.'), findsOneWidget);
    expect(find.text('아직 모아볼 사진이 없어요.'), findsNothing);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('start-photo-selection')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('전체 사진 요청 오류는 다시 시도 가능한 상태를 표시한다', (tester) async {
    await pumpAlbum(
      tester,
      repository: _FakeMemoryAlbumRepository(
        albums: [album],
        photoError: StateError('offline'),
      ),
    );
    await _openAllPhotos(tester);

    expect(find.text('전체 사진을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('선택 사진은 대상 앨범과 재확인 후 repository 이동 action에 연결된다', (tester) async {
    var moveCallCount = 0;
    String? movedDestination;
    Iterable<String>? movedIds;
    final repository = _FakeMemoryAlbumRepository(
      albums: [album, destinationAlbum],
      photos: [photos.first],
      onMovePhotos: (receivedCoupleId, photoIds, destinationAlbumId) async {
        expect(receivedCoupleId, coupleId);
        moveCallCount++;
        movedDestination = destinationAlbumId;
        movedIds = photoIds.toList();
        return 1;
      },
    );
    await pumpAlbum(
      tester,
      repository: repository,
    );
    await _openAllPhotos(tester);

    await tester.longPress(
      find.byKey(const ValueKey('memory-photo-photo-1.jpg')),
    );
    await tester.pump();
    expect(find.text('1장 선택'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('move-selected-memory-photos')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('move-destination-album-2')));
    await tester.pumpAndSettle();
    expect(find.text('가을 산책(으)로 옮길까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '이동'));
    await tester.pumpAndSettle();

    expect(moveCallCount, 1);
    expect(movedDestination, 'album-2');
    expect(movedIds, ['photo-1']);
    expect(find.text('사진 1장을 가을 산책(으)로 옮겼어요.'), findsOneWidget);
  });

  testWidgets('200% 큰 글자에서도 필터와 선택 작업줄이 overflow 없이 동작한다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpAlbum(tester, photos: [photos.first]);
    await _openAllPhotos(tester);
    await tester.tap(find.byKey(const ValueKey('start-photo-selection')));
    await tester.tap(find.byKey(const ValueKey('memory-photo-photo-1.jpg')));
    await tester.pump();

    expect(find.byKey(const ValueKey('all-photo-date-filter')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('move-selected-memory-photos')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openAllPhotos(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('전체 보기'),
    260,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text('전체 보기'));
  await tester.pumpAndSettle();
}

class _FakeMemoryAlbumRepository extends MemoryAlbumRepository {
  _FakeMemoryAlbumRepository({
    required this.albums,
    this.photos = const [],
    this.photoError,
    this.onDeletePhotos,
    this.onMovePhotos,
    this.onFetchAlbumPage,
  }) : super(
          client: SupabaseClient(
            'http://localhost:54321',
            'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final List<MemoryAlbum> albums;
  final List<MemoryAlbumPhoto> photos;
  final Object? photoError;
  final Future<int> Function(String coupleId, Iterable<String> photoIds)?
      onDeletePhotos;
  final Future<int> Function(
    String coupleId,
    Iterable<String> photoIds,
    String destinationAlbumId,
  )? onMovePhotos;
  final Future<MemoryAlbumListPage> Function(MemoryAlbumCursor? cursor)?
      onFetchAlbumPage;
  String? lastUploadedBy;
  String? lastExcludedUploader;
  DateTime? lastCreatedAtOrAfter;
  DateTime? lastCreatedAtBefore;

  @override
  Stream<List<MemoryAlbum>> watchAlbums(String coupleId) {
    return Stream.value(albums);
  }

  @override
  Stream<MemoryAlbumHeadSnapshot> watchAlbumHead({
    required String coupleId,
    int limit = memoryAlbumPageSize,
  }) {
    final items = mergeMemoryAlbums(const [], albums.take(limit));
    return Stream.value(
      MemoryAlbumHeadSnapshot(
        items: items,
        oldest: items.isEmpty ? null : items.last,
        isExhaustive: albums.length <= limit,
      ),
    );
  }

  @override
  Future<MemoryAlbumListPage> fetchAlbumPage({
    required String coupleId,
    MemoryAlbumCursor? cursor,
    int pageSize = memoryAlbumPageSize,
  }) async {
    final callback = onFetchAlbumPage;
    if (callback != null) return callback(cursor);
    return memoryAlbumPageFromRows(albums, pageSize: pageSize);
  }

  @override
  Stream<List<MemoryAlbumPhoto>> watchRecentPhotos({
    required String coupleId,
    int limit = 10,
  }) {
    return Stream.value(const []);
  }

  @override
  Stream<List<MemoryAlbumPhotoDeletion>> watchPhotoDeletions({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumDeletionEventWindow,
  }) {
    return Stream.value(const []);
  }

  @override
  Stream<List<MemoryAlbumPhoto>> watchPhotoHead({
    required String coupleId,
    String? albumId,
    int limit = memoryAlbumPhotoPageSize,
    DateTime? createdAtOrAfter,
    DateTime? createdAtBefore,
    String? uploadedBy,
    String? excludedUploader,
  }) {
    return watchPhotoHeadWindow(
      coupleId: coupleId,
      albumId: albumId,
      limit: limit,
      createdAtOrAfter: createdAtOrAfter,
      createdAtBefore: createdAtBefore,
      uploadedBy: uploadedBy,
      excludedUploader: excludedUploader,
    ).map((snapshot) => snapshot.items);
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
    if (photoError != null) return Stream.error(photoError!);
    lastUploadedBy = uploadedBy;
    lastExcludedUploader = excludedUploader;
    lastCreatedAtOrAfter = createdAtOrAfter;
    lastCreatedAtBefore = createdAtBefore;
    return Stream.value(
      MemoryAlbumPhotoHeadSnapshot(
        items: filterMemoryAlbumPhotos(
          photos,
          createdAtOrAfter: createdAtOrAfter,
          createdAtBefore: createdAtBefore,
          uploadedBy: uploadedBy,
          excludedUploader: excludedUploader,
        ),
        oldestUnfiltered: photos.isEmpty ? null : photos.last,
        isExhaustive: photos.length < limit,
      ),
    );
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
  }) async {
    if (photoError != null) throw photoError!;
    lastUploadedBy = uploadedBy;
    lastExcludedUploader = excludedUploader;
    lastCreatedAtOrAfter = createdAtOrAfter;
    lastCreatedAtBefore = createdAtBefore;
    return memoryAlbumPhotoPageFromRows(
      filterMemoryAlbumPhotos(
        photos,
        createdAtOrAfter: createdAtOrAfter,
        createdAtBefore: createdAtBefore,
        uploadedBy: uploadedBy,
        excludedUploader: excludedUploader,
      ),
      pageSize: pageSize,
    );
  }

  @override
  Future<int> deletePhotos({
    required String coupleId,
    required Iterable<String> photoIds,
  }) {
    return onDeletePhotos?.call(coupleId, photoIds) ?? Future.value(0);
  }

  @override
  Future<int> movePhotos({
    required String coupleId,
    required Iterable<String> photoIds,
    required String destinationAlbumId,
  }) {
    return onMovePhotos?.call(coupleId, photoIds, destinationAlbumId) ??
        Future.value(0);
  }
}
