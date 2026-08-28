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
  final now = DateTime.now();
  final fixtureToday = DateTime(now.year, now.month, now.day, 12);
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
    createdAt: fixtureToday.subtract(const Duration(days: 11)),
    updatedAt: fixtureToday,
    photoCount: 0,
    isFeatured: true,
  );
  final destinationAlbum = MemoryAlbum(
    id: 'album-2',
    coupleId: coupleId,
    name: '가을 산책',
    createdBy: 'user-2',
    createdAt: fixtureToday.subtract(const Duration(days: 10)),
    updatedAt: fixtureToday.subtract(const Duration(days: 1)),
    photoCount: 0,
  );
  final photos = [
    MemoryAlbumPhoto(
      id: 'photo-1',
      albumId: 'album-1',
      coupleId: coupleId,
      storagePath: 'photo-1.jpg',
      uploadedBy: 'user-1',
      createdAt: fixtureToday,
    ),
    MemoryAlbumPhoto(
      id: 'photo-2',
      albumId: 'album-1',
      coupleId: coupleId,
      storagePath: 'photo-2.jpg',
      uploadedBy: 'user-2',
      createdAt: fixtureToday.subtract(const Duration(days: 1)),
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
        createdAt: fixtureToday.subtract(Duration(days: index)),
        updatedAt: fixtureToday.subtract(Duration(days: index)),
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

  testWidgets('앨범 다음 페이지 실패는 상단 새로고침 오류로 오인하지 않고 cursor 재시도한다', (tester) async {
    final manyAlbums = List<MemoryAlbum>.generate(
      31,
      (index) => MemoryAlbum(
        id: 'paged-album-${index + 1}',
        coupleId: coupleId,
        name: index == 30 ? '재시도로 불러온 앨범' : '페이지 앨범 ${index + 1}',
        createdBy: 'user-1',
        createdAt: fixtureToday.subtract(Duration(days: index)),
        updatedAt: fixtureToday.subtract(Duration(days: index)),
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
        if (pageCalls == 2) throw StateError('load more offline');
        return MemoryAlbumListPage(
          items: [manyAlbums.last],
          nextCursor: null,
          hasMore: false,
        );
      },
    );
    await pumpAlbum(tester, repository: repository);

    for (var index = 0; index < 4 && pageCalls < 2; index++) {
      await tester.fling(
        find.byType(ListView),
        const Offset(0, -1400),
        5000,
      );
      await tester.pumpAndSettle();
    }

    expect(find.byKey(const ValueKey('retry-album-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('album-feed-inline-error')), findsNothing);
    expect(find.text('페이지 앨범 1'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('retry-album-page')));
    await tester.pumpAndSettle();
    expect(pageCalls, 3);
    expect(find.text('재시도로 불러온 앨범'), findsOneWidget);
  });

  testWidgets('앨범 새로고침 실패와 재시도 중에도 기존 앨범을 보존한다', (tester) async {
    final retry = Completer<MemoryAlbumListPage>();
    var pageCalls = 0;
    final repository = _FakeMemoryAlbumRepository(
      albums: [album],
      onFetchAlbumPage: (_) {
        pageCalls++;
        if (pageCalls == 1) {
          return Future.value(memoryAlbumPageFromRows([album]));
        }
        if (pageCalls == 2) {
          return Future.error(StateError('refresh offline'));
        }
        return retry.future;
      },
    );
    await pumpAlbum(tester, repository: repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MemoryAlbumPage)),
    );

    await container.read(memoryAlbumFeedProvider(coupleId).notifier).refresh();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('album-cover-card-album-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('album-feed-inline-error')),
      findsOneWidget,
    );
    expect(find.textContaining('기존 앨범은 그대로'), findsOneWidget);

    await tester.tap(find.text('다시 연결하기'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('album-feed-refreshing')),
      findsOneWidget,
    );
    expect(find.text('앨범을 다시 불러오는 중'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('album-cover-card-album-1')),
      findsOneWidget,
    );

    retry.complete(memoryAlbumPageFromRows([album]));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('album-feed-inline-error')),
      findsNothing,
    );
  });

  testWidgets('실시간 앨범 연결 오류는 현재 콘텐츠 위에 별도 안내한다', (tester) async {
    final head = StreamController<MemoryAlbumHeadSnapshot>();
    addTearDown(head.close);
    await pumpAlbum(
      tester,
      repository: _FakeMemoryAlbumRepository(
        albums: [album],
        albumHeadStream: head.stream,
      ),
    );

    head.addError(StateError('realtime offline'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('album-cover-card-album-1')),
      findsOneWidget,
    );
    expect(find.textContaining('새 앨범 소식을 연결하지 못했어요'), findsOneWidget);
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
    expect(
      find.byKey(const ValueKey('album-empty-cover-artwork')),
      findsOneWidget,
    );
  });

  testWidgets('새 앨범 시트는 이름과 선택 표지만 묻고 표지 없이 만들 수 있다', (tester) async {
    Uint8List? receivedCoverBytes;
    String? receivedName;
    var albumPageCalls = 0;
    final repository = _FakeMemoryAlbumRepository(
      albums: const [],
      onFetchAlbumPage: (_) async {
        albumPageCalls++;
        return memoryAlbumPageFromRows(const []);
      },
    );
    await pumpAlbum(
      tester,
      repository: repository,
      overrides: [
        createMemoryAlbumProvider.overrideWithValue(({
          required String coupleId,
          required String name,
          Uint8List? coverBytes,
          String? coverExtension,
        }) async {
          receivedName = name;
          receivedCoverBytes = coverBytes;
          return MemoryAlbum(
            id: 'created-album',
            coupleId: coupleId,
            name: name,
            createdBy: 'user-1',
            createdAt: fixtureToday,
            updatedAt: fixtureToday,
          );
        }),
      ],
    );

    await tester.tap(find.text('첫 앨범 만들기'));
    await tester.pumpAndSettle();

    expect(find.text('앨범 이름'), findsOneWidget);
    expect(find.text('표지 사진 (선택)'), findsOneWidget);
    expect(find.text('취소'), findsOneWidget);
    expect(find.text('선택 취소'), findsNothing);
    expect(find.text('사진 선택'), findsNothing);
    expect(
      find.byKey(const ValueKey('album-sheet-default-cover')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '표지 없는 앨범');
    await tester.pump();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('submit-album-sheet')),
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('submit-album-sheet')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('submit-album-sheet')));
    await tester.pumpAndSettle();

    expect(receivedName, '표지 없는 앨범');
    expect(receivedCoverBytes, isNull);
    expect(albumPageCalls, 2);
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

  testWidgets('전체 사진 새로고침 실패와 재시도 중에도 기존 사진을 보존한다', (tester) async {
    final retry = Completer<MemoryAlbumPhotoPage>();
    var pageCalls = 0;
    final repository = _FakeMemoryAlbumRepository(
      albums: [album],
      photos: [photos.first],
      onFetchPhotoPage: (_) {
        pageCalls++;
        if (pageCalls == 1) {
          return Future.value(memoryAlbumPhotoPageFromRows([photos.first]));
        }
        if (pageCalls == 2) {
          return Future.error(StateError('refresh offline'));
        }
        return retry.future;
      },
    );
    await pumpAlbum(tester, repository: repository);
    await _openAllPhotos(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.text('전체 사진')),
    );
    const args = MemoryAlbumPhotoFeedArgs(coupleId: coupleId);

    await container.read(memoryAlbumPhotoFeedProvider(args).notifier).refresh();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('memory-photo-photo-1.jpg')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('all-photo-feed-inline-error')),
      findsOneWidget,
    );
    expect(find.textContaining('기존 사진은 그대로'), findsOneWidget);

    await tester.tap(find.text('다시 연결하기'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('all-photo-feed-refreshing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('memory-photo-photo-1.jpg')),
      findsOneWidget,
    );

    retry.complete(memoryAlbumPhotoPageFromRows([photos.first]));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('all-photo-feed-inline-error')),
      findsNothing,
    );
  });

  testWidgets('실시간 사진 연결 오류는 현재 사진 위에 별도 안내한다', (tester) async {
    final head = StreamController<MemoryAlbumPhotoHeadSnapshot>();
    addTearDown(head.close);
    await pumpAlbum(
      tester,
      repository: _FakeMemoryAlbumRepository(
        albums: [album],
        photos: [photos.first],
        photoHeadStream: head.stream,
      ),
    );
    await _openAllPhotos(tester);

    head.addError(StateError('photo realtime offline'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('memory-photo-photo-1.jpg')),
      findsOneWidget,
    );
    expect(find.textContaining('새 사진 소식을 연결하지 못했어요'), findsOneWidget);
  });

  testWidgets('사진 선택 모드는 명시적 취소와 44pt 선택 semantics를 제공한다', (tester) async {
    await pumpAlbum(tester, photos: [photos.first]);
    await _openAllPhotos(tester);

    await tester.tap(find.byKey(const ValueKey('start-photo-selection')));
    await tester.pump();

    final cancel = find.byKey(const ValueKey('cancel-photo-selection'));
    final semantics = find.byKey(
      const ValueKey('memory-photo-semantics-photo-1.jpg'),
    );
    expect(cancel, findsOneWidget);
    expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(semantics).width, greaterThanOrEqualTo(44));
    expect(tester.widget<Semantics>(semantics).properties.selected, isFalse);

    await tester.tap(find.byKey(const ValueKey('memory-photo-photo-1.jpg')));
    await tester.pump();
    expect(tester.widget<Semantics>(semantics).properties.selected, isTrue);
    expect(find.text('1장 선택'), findsOneWidget);

    await tester.tap(cancel);
    await tester.pump();
    expect(find.byKey(const ValueKey('start-photo-selection')), findsOneWidget);
  });

  testWidgets('개별 사진 signed URL 실패는 해당 타일에서 다시 시도할 수 있다', (tester) async {
    final retryPhoto = MemoryAlbumPhoto(
      id: 'retry-photo',
      albumId: album.id,
      coupleId: coupleId,
      storagePath: 'retry-photo.jpg',
      uploadedBy: 'user-1',
      createdAt: fixtureToday,
    );
    var signedUrlCalls = 0;
    await pumpAlbum(
      tester,
      photos: [retryPhoto],
      overrides: [
        createMemoryAlbumPhotoUrlsProvider.overrideWithValue((paths) async {
          signedUrlCalls++;
          if (signedUrlCalls == 1) throw StateError('signed url failed');
          return paths
              .map((path) => 'https://example.invalid/retried/$path')
              .toList();
        }),
      ],
    );
    await _openAllPhotos(tester);

    final retryButton = find.byKey(
      const ValueKey('retry-memory-photo-retry-photo.jpg'),
    );
    expect(retryButton, findsOneWidget);

    await tester.tap(find.byTooltip('사진 다시 불러오기'));
    await tester.pump();
    expect(signedUrlCalls, 2);
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
    this.onFetchPhotoPage,
    this.albumHeadStream,
    this.photoHeadStream,
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
  final Future<MemoryAlbumPhotoPage> Function(MemoryAlbumPhotoCursor? cursor)?
      onFetchPhotoPage;
  final Stream<MemoryAlbumHeadSnapshot>? albumHeadStream;
  final Stream<MemoryAlbumPhotoHeadSnapshot>? photoHeadStream;
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
    final customStream = albumHeadStream;
    if (customStream != null) return customStream;
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
    final customStream = photoHeadStream;
    if (customStream != null) return customStream;
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
    final callback = onFetchPhotoPage;
    if (callback != null) return callback(cursor);
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
