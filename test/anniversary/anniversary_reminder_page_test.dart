import 'dart:async';

import 'package:couple_chat_app/src/features/anniversary/data/anniversary_providers.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_repository.dart';
import 'package:couple_chat_app/src/features/anniversary/presentation/anniversary_reminder_page.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_preferences.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('기념일 대시보드가 히어로와 다가오는 목록을 표시한다', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final anniversaryDate = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 981)),
    );
    final thousandDay = anniversaryDate.add(const Duration(days: 999));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'user-1',
              nickname: '하루',
              pairingCode: 'ABCD',
              coupleId: 'couple-1',
              avatarPath: null,
            ),
          ),
          anniversaryDateProvider.overrideWith(
            (ref) => Stream.value(anniversaryDate),
          ),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, coupleId) => Stream.value(
              const {
                'user-1': 'https://example.com/me.jpg',
                'user-2': 'https://example.com/partner.jpg',
              },
            ),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <AnniversaryItem>[]),
          ),
          fetchAnniversaryTimelinePageProvider.overrideWithValue(
            ({
              required coupleId,
              cursor,
              pageSize = 15,
            }) async {
              final all = buildUpcomingAnniversaryTimeline(
                relationshipStart: anniversaryDate,
                customItems: const <AnniversaryItem>[],
                limit: 200,
              );
              final start = cursor == null
                  ? 0
                  : all.indexWhere(
                      (item) =>
                          item.eventDate.isAfter(cursor.eventDate) ||
                          (DateUtils.isSameDay(
                                item.eventDate,
                                cursor.eventDate,
                              ) &&
                              item.stableId.compareTo(cursor.stableId) > 0),
                    );
              final safeStart = start < 0 ? all.length : start;
              final end = (safeStart + pageSize).clamp(0, all.length).toInt();
              final items = all.sublist(safeStart, end);
              final last = items.isEmpty ? null : items.last;
              return AnniversaryTimelinePage(
                items: items,
                nextCursor: last == null
                    ? null
                    : AnniversaryTimelineCursor(
                        eventDate: last.eventDate,
                        stableId: last.stableId,
                      ),
                hasMore: end < all.length,
              );
            },
          ),
          notificationPreferencesProvider.overrideWith(
            (ref, userId) =>
                Stream.value(NotificationPreferences.defaults(userId)),
          ),
          addAnniversaryProvider.overrideWithValue(
            ({
              required coupleId,
              required title,
              required eventDate,
              required repeat,
              required reminderEnabled,
              required reminderDaysBefore,
              required reminderHour,
              note,
              linkedAlbumId,
            }) async {},
          ),
        ],
        child: const MaterialApp(
          home: AnniversaryReminderPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('기념일'), findsOneWidget);
    expect(find.text('우리의 기념일'), findsOneWidget);
    expect(
      find.text('${anniversaryDateKoreanLabel(anniversaryDate)}부터 함께'),
      findsOneWidget,
    );
    expect(find.text('다가오는 기념일'), findsOneWidget);
    expect(find.text('1000일까지 18일 남았어요'), findsOneWidget);
    expect(find.text('2번째 기념일이에요'), findsNothing);
    expect(find.text('1000일'), findsOneWidget);
    expect(find.text(_testDateWithWeekdayLabel(thousandDay)), findsOneWidget);
    expect(find.text('3주년'), findsOneWidget);
    expect(find.text('1100일'), findsOneWidget);
    expect(find.text('1300일'), findsOneWidget);
    expect(find.text('1400일'), findsNothing);
    expect(find.text('알림 설정'), findsOneWidget);

    final assetNames = tester
        .widgetList<Image>(find.byType(Image))
        .map(_assetName)
        .whereType<String>()
        .toSet();

    expect(
      assetNames,
      containsAll(
        const [
          'assets/images/anniversary/anniv_hero_ring.png',
          'assets/images/anniversary/anniv_event_ring.png',
          'assets/images/anniversary/anniv_event_heart.png',
        ],
      ),
    );
    for (final operationalGlyph in const [
      'assets/images/anniversary/anniv_more_dots.png',
      'assets/images/anniversary/anniv_bell.png',
      'assets/images/anniversary/anniv_chevron_right.png',
      'assets/images/anniversary/anniv_add_plus.png',
    ]) {
      expect(assetNames, isNot(contains(operationalGlyph)));
    }
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_rounded), findsWidgets);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    final decorativeChevrons = find.byIcon(Icons.chevron_right_rounded);
    expect(decorativeChevrons, findsWidgets);
    expect(
      find
          .ancestor(
            of: decorativeChevrons,
            matching: find.byType(ExcludeSemantics),
          )
          .evaluate()
          .length,
      decorativeChevrons.evaluate().length,
    );

    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      if (_assetName(image) != null) {
        expect(image.image, isA<ResizeImage>());
      }
    }
    final heroImage = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            _assetName(widget) ==
                'assets/images/anniversary/anniv_hero_ring.png' &&
            widget.width == 224,
      ),
    );
    final resizedHero = heroImage.image as ResizeImage;
    expect(resizedHero.width, 224);
    expect(resizedHero.height, 136);

    for (final control in [
      find.bySemanticsLabel('더보기'),
      find.bySemanticsLabel('기념일 추가'),
      find.bySemanticsLabel('알림 켜짐').first,
    ]) {
      final size = tester.getSize(control);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(
        tester
            .getSemantics(control)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    }
    expect(find.byTooltip('더보기'), findsOneWidget);
    expect(find.byTooltip('기념일 추가'), findsOneWidget);
    expect(find.byTooltip('알림 켜짐'), findsWidgets);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('알림 켜짐').first)
          .getSemanticsData()
          .flagsCollection
          .isToggled
          .toBoolOrNull(),
      isTrue,
    );

    final hasDdayChip = tester
        .widgetList<Text>(find.byType(Text))
        .any((text) => text.data?.startsWith('D-') ?? false);
    expect(hasDdayChip, isTrue);
    semantics.dispose();
  });

  testWidgets('전체 기념일은 좌측 뒤로가기와 스크롤 페이징을 제공한다', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1080, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final anniversaryDate = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 981)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'user-1',
              nickname: '하루',
              pairingCode: 'ABCD',
              coupleId: 'couple-1',
              avatarPath: null,
            ),
          ),
          anniversaryDateProvider.overrideWith(
            (ref) => Stream.value(anniversaryDate),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <AnniversaryItem>[]),
          ),
          fetchAnniversaryTimelinePageProvider.overrideWithValue(
            ({
              required coupleId,
              cursor,
              pageSize = 15,
            }) =>
                _fakeTimelinePage(
              anniversaryDate: anniversaryDate,
              cursor: cursor,
              pageSize: pageSize,
            ),
          ),
          notificationPreferencesProvider.overrideWith(
            (ref, userId) =>
                Stream.value(NotificationPreferences.defaults(userId)),
          ),
        ],
        child: const MaterialApp(
          home: AnniversaryFullListPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('전체 기념일'), findsOneWidget);
    expect(find.bySemanticsLabel('뒤로가기'), findsOneWidget);
    expect(find.byTooltip('뒤로가기'), findsOneWidget);
    final backButton = find.bySemanticsLabel('뒤로가기');
    expect(tester.getSize(backButton).shortestSide, greaterThanOrEqualTo(44));
    expect(
      tester
          .getSemantics(backButton)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(find.text('3주년'), findsOneWidget);
    expect(find.text('15개 더 보기'), findsNothing);
    expect(find.text('2200일'), findsNothing);

    for (var i = 0; i < 50 && find.text('2200일').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable), const Offset(0, -700));
      await tester.pump();
    }
    expect(find.text('2200일'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('사용자 기념일은 선물 이미지와 실제 수정 및 삭제 상세를 제공한다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final customItem = AnniversaryItem(
      id: 'custom-1',
      coupleId: 'couple-1',
      title: '첫 여행',
      eventDate: DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 2)),
      ),
      createdAt: DateTime(2026, 1, 1),
      repeat: AnniversaryRepeat.yearly,
      reminderDaysBefore: 3,
      reminderHour: 10,
      note: '눈 내리던 날 함께 떠난 첫 여행',
      linkedAlbumId: 'album-1',
    );
    String? updatedTitle;
    AnniversaryRepeat? updatedRepeat;
    int? updatedReminderDays;
    int? updatedReminderHour;
    String? updatedNote;
    String? updatedLinkedAlbumId;
    String? removedId;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'user-1',
              nickname: '하루',
              pairingCode: 'ABCD',
              coupleId: 'couple-1',
              avatarPath: null,
            ),
          ),
          anniversaryDateProvider.overrideWith((ref) => Stream.value(null)),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <String, String>{}),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => Stream.value([customItem]),
          ),
          memoryAlbumsProvider.overrideWith(
            (ref, coupleId) => Stream.value([
              MemoryAlbum(
                id: 'album-1',
                coupleId: coupleId,
                name: '겨울 여행',
                createdBy: 'user-1',
                createdAt: DateTime(2026, 1, 1),
                updatedAt: DateTime(2026, 1, 1),
              ),
            ]),
          ),
          notificationPreferencesProvider.overrideWith(
            (ref, userId) =>
                Stream.value(NotificationPreferences.defaults(userId)),
          ),
          updateAnniversaryProvider.overrideWithValue(
            ({
              required id,
              required title,
              required eventDate,
              required repeat,
              required reminderEnabled,
              required reminderDaysBefore,
              required reminderHour,
              note,
              linkedAlbumId,
            }) async {
              updatedTitle = title;
              updatedRepeat = repeat;
              updatedReminderDays = reminderDaysBefore;
              updatedReminderHour = reminderHour;
              updatedNote = note;
              updatedLinkedAlbumId = linkedAlbumId;
            },
          ),
          removeAnniversaryProvider.overrideWithValue((id) async {
            removedId = id;
          }),
        ],
        child: const MaterialApp(home: AnniversaryReminderPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('첫 여행'), findsOneWidget);
    final assetNames = tester
        .widgetList<Image>(find.byType(Image))
        .map(_assetName)
        .whereType<String>();
    expect(
      assetNames,
      contains('assets/images/anniversary/anniv_event_gift.png'),
    );
    expect(find.bySemanticsLabel('알림 켜짐'), findsOneWidget);

    await tester.tap(find.text('첫 여행'));
    await tester.pumpAndSettle();
    expect(find.text('기념일 상세'), findsOneWidget);
    expect(find.text('매년'), findsOneWidget);
    expect(find.text('3일 전 오전 10시'), findsOneWidget);
    expect(find.text('눈 내리던 날 함께 떠난 첫 여행'), findsOneWidget);
    expect(find.text('추억 앨범 연결됨'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('edit-anniversary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('anniversary-title-field')),
      '첫 해외여행',
    );
    await tester.tap(find.byKey(const ValueKey('save-anniversary')));
    await tester.pumpAndSettle();
    expect(updatedTitle, '첫 해외여행');
    expect(updatedRepeat, AnniversaryRepeat.yearly);
    expect(updatedReminderDays, 3);
    expect(updatedReminderHour, 10);
    expect(updatedNote, '눈 내리던 날 함께 떠난 첫 여행');
    expect(updatedLinkedAlbumId, 'album-1');

    await tester.tap(find.text('첫 여행'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-anniversary')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-anniversary-delete')),
    );
    await tester.pumpAndSettle();
    expect(removedId, 'custom-1');
  });

  testWidgets('추가 저장 뒤 실시간 스트림 항목이 대시보드에 즉시 나타난다', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = StreamController<List<AnniversaryItem>>.broadcast();
    addTearDown(controller.close);
    var addCalls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'user-1',
              nickname: '하루',
              pairingCode: 'ABCD',
              coupleId: 'couple-1',
              avatarPath: null,
            ),
          ),
          anniversaryDateProvider.overrideWith((ref) => Stream.value(null)),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <String, String>{}),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => controller.stream,
          ),
          memoryAlbumsProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <MemoryAlbum>[]),
          ),
          notificationPreferencesProvider.overrideWith(
            (ref, userId) =>
                Stream.value(NotificationPreferences.defaults(userId)),
          ),
          addAnniversaryProvider.overrideWithValue(
            ({
              required coupleId,
              required title,
              required eventDate,
              required repeat,
              required reminderEnabled,
              required reminderDaysBefore,
              required reminderHour,
              note,
              linkedAlbumId,
            }) async {
              addCalls += 1;
              controller.add([
                AnniversaryItem(
                  id: 'new-item',
                  coupleId: coupleId,
                  title: title,
                  eventDate: eventDate,
                  createdAt: DateTime.now(),
                  repeat: repeat,
                  reminderEnabled: reminderEnabled,
                  reminderDaysBefore: reminderDaysBefore,
                  reminderHour: reminderHour,
                ),
              ]);
            },
          ),
        ],
        child: const MaterialApp(home: AnniversaryReminderPage()),
      ),
    );
    await tester.pumpAndSettle();
    controller.add(const <AnniversaryItem>[]);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-anniversary')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('anniversary-title-field')),
      '새 약속',
    );
    await tester.tap(find.byKey(const ValueKey('save-anniversary')));
    await tester.pumpAndSettle();

    expect(addCalls, 1);
    expect(find.text('새 약속'), findsOneWidget);
  });

  testWidgets('알림 딥링크는 미리보기 5개 밖의 사용자 기념일도 정확히 연다', (tester) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final items = List<AnniversaryItem>.generate(
      6,
      (index) => AnniversaryItem(
        id: 'custom-${index + 1}',
        coupleId: 'couple-1',
        title: index == 5 ? '여섯 번째 약속' : '${index + 1}번째 약속',
        eventDate: today.add(Duration(days: index + 1)),
        createdAt: DateTime(2026, 1, index + 1),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'user-1',
              nickname: '하루',
              pairingCode: 'ABCD',
              coupleId: 'couple-1',
              avatarPath: null,
            ),
          ),
          anniversaryDateProvider.overrideWith((ref) => Stream.value(null)),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <String, String>{}),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => Stream.value(items),
          ),
          notificationPreferencesProvider.overrideWith(
            (ref, userId) =>
                Stream.value(NotificationPreferences.defaults(userId)),
          ),
        ],
        child: const MaterialApp(
          home: AnniversaryReminderPage(initialEntryId: 'custom-6'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('기념일 상세'), findsOneWidget);
    expect(find.text('여섯 번째 약속'), findsOneWidget);
  });

  testWidgets('지난 비반복 기념일 딥링크도 미래 타임라인이 비어 있을 때 정확히 연다', (tester) async {
    final pastItem = AnniversaryItem(
      id: 'past-custom',
      coupleId: 'couple-1',
      title: '지난 첫 약속',
      eventDate: DateUtils.dateOnly(
        DateTime.now().subtract(const Duration(days: 30)),
      ),
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'user-1',
              nickname: '하루',
              pairingCode: 'ABCD',
              coupleId: 'couple-1',
              avatarPath: null,
            ),
          ),
          anniversaryDateProvider.overrideWith((ref) => Stream.value(null)),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <String, String>{}),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => Stream.value([pastItem]),
          ),
          notificationPreferencesProvider.overrideWith(
            (ref, userId) =>
                Stream.value(NotificationPreferences.defaults(userId)),
          ),
        ],
        child: const MaterialApp(
          home: AnniversaryReminderPage(initialEntryId: 'past-custom'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('기념일 상세'), findsOneWidget);
    expect(find.text('지난 첫 약속'), findsOneWidget);
  });

  testWidgets('390x844 화면과 200% 글자 크기에서도 핵심 화면이 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final start = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 300)),
    );
    final customItem = AnniversaryItem(
      id: 'long-title',
      coupleId: 'couple-1',
      title: '처음으로 함께 떠났던 아주 특별한 여름 여행 기념일',
      eventDate: DateUtils.dateOnly(
        DateTime.now().add(const Duration(days: 1)),
      ),
      createdAt: DateTime(2026, 1, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'user-1',
              nickname: '아주 긴 이름을 사용하는 사용자',
              pairingCode: 'ABCD',
              coupleId: 'couple-1',
              avatarPath: null,
            ),
          ),
          anniversaryDateProvider.overrideWith((ref) => Stream.value(start)),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, coupleId) => Stream.value(const <String, String>{}),
          ),
          anniversaryItemsProvider.overrideWith(
            (ref, coupleId) => Stream.value([customItem]),
          ),
          notificationPreferencesProvider.overrideWith(
            (ref, userId) =>
                Stream.value(NotificationPreferences.defaults(userId)),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const AnniversaryReminderPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('기념일'), findsOneWidget);
    expect(find.text('다가오는 기념일'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('처음으로 함께 떠났던 아주 특별한 여름 여행 기념일'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

String? _assetName(Image image) {
  final provider = image.image;
  if (provider is AssetImage) {
    return provider.assetName;
  }
  if (provider is ResizeImage && provider.imageProvider is AssetImage) {
    return (provider.imageProvider as AssetImage).assetName;
  }
  return null;
}

Future<AnniversaryTimelinePage> _fakeTimelinePage({
  required DateTime anniversaryDate,
  required AnniversaryTimelineCursor? cursor,
  required int pageSize,
}) async {
  final all = buildUpcomingAnniversaryTimeline(
    relationshipStart: anniversaryDate,
    customItems: const <AnniversaryItem>[],
    limit: 200,
  );
  final start = cursor == null
      ? 0
      : all.indexWhere(
          (item) =>
              item.eventDate.isAfter(cursor.eventDate) ||
              (DateUtils.isSameDay(item.eventDate, cursor.eventDate) &&
                  item.stableId.compareTo(cursor.stableId) > 0),
        );
  final safeStart = start < 0 ? all.length : start;
  final end = (safeStart + pageSize).clamp(0, all.length).toInt();
  final items = all.sublist(safeStart, end);
  final last = items.isEmpty ? null : items.last;
  return AnniversaryTimelinePage(
    items: items,
    nextCursor: last == null
        ? null
        : AnniversaryTimelineCursor(
            eventDate: last.eventDate,
            stableId: last.stableId,
          ),
    hasMore: end < all.length,
  );
}

String _testDateWithWeekdayLabel(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  final normalized = DateUtils.dateOnly(date);
  return '${anniversaryDateKoreanLabel(normalized)} (${weekdays[normalized.weekday - 1]})';
}
