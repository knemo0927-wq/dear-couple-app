import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/anniversary/data/anniversary_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/memory_album_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_list_page.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_shell_page.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_inbox.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('홈은 375pt·200% 글자에서 핵심 문구를 줄이지 않고 hero tap을 설명한다',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpAccessibleHome(
      tester,
      size: const Size(375, 812),
      textScale: 2,
    );

    final hero = find.byKey(const ValueKey('relationship-hero'));
    final heroSemantics = tester.getSemantics(hero);
    final greeting = tester.widget<Text>(
      find.byKey(const ValueKey('home-greeting-title')),
    );
    final chatTitle = tester.widget<Text>(
      find.byKey(const ValueKey('primary-chat-title')),
    );
    final preview = tester.widget<Text>(
      find.byKey(const ValueKey('primary-chat-preview')),
    );

    expect(find.text('우리의 연애'), findsOneWidget);
    expect(tester.getSize(hero).height, greaterThan(168));
    expect(
      find.descendant(of: hero, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(heroSemantics.label, contains('기념일'));
    expect(
      heroSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.getSize(hero).shortestSide, greaterThanOrEqualTo(44));
    expect(greeting.maxLines, isNull);
    expect(greeting.overflow, isNot(TextOverflow.ellipsis));
    expect(chatTitle.maxLines, isNull);
    expect(chatTitle.overflow, isNot(TextOverflow.ellipsis));
    expect(preview.maxLines, isNull);
    expect(preview.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('홈 채팅 아바타는 내부 여백 없이 원형 프레임을 사진으로 채운다', (tester) async {
    await _pumpAccessibleHome(
      tester,
      size: const Size(375, 812),
      textScale: 1,
      avatarUrls: const <String, String>{
        'user-2': 'https://example.invalid/partner-avatar.jpg',
      },
    );

    final avatarFinder = find.byKey(const ValueKey('primary-chat-avatar'));
    final avatar = tester.widget<Container>(avatarFinder);
    final foreground = avatar.foregroundDecoration! as BoxDecoration;
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('primary-chat-avatar-image')),
    );

    expect(avatar.padding, isNull);
    expect(avatar.decoration, isNull);
    expect(foreground.color, isNull);
    expect(foreground.shape, BoxShape.circle);
    expect(foreground.border, isNotNull);
    expect(
      find.descendant(of: avatarFinder, matching: find.byType(ClipOval)),
      findsOneWidget,
    );
    expect(tester.getSize(avatarFinder), const Size.square(56));
    expect(image.fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
  });

  for (final size in <Size>[const Size(430, 932), const Size(375, 812)]) {
    testWidgets('홈 ${size.width.toInt()}pt 기본 글자에서 빠른 실행 3카드가 중앙 정렬된다',
        (tester) async {
      await _pumpAccessibleHome(tester, size: size, textScale: 1);
      await _revealQuickActions(tester);

      expect(find.byType(GridView), findsOneWidget);
      _expectQuickActionCenters(tester);
      _expectCompactQuickActionRowsAligned(tester);
      for (final glyph in _quickActionGlyphs) {
        expect(
          tester.getSize(find.byKey(ValueKey('quick-action-$glyph'))).height,
          122,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('홈은 320pt 기본 글자에서도 좁은 카드를 만들지 않고 1열로 전환한다', (tester) async {
    await _pumpAccessibleHome(
      tester,
      size: const Size(320, 568),
      textScale: 1,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: '320pt 홈의 최초 레이아웃부터 overflow가 없어야 합니다.',
    );
    await _revealQuickActions(tester);

    expect(find.byType(GridView), findsNothing);
    _expectSingleColumnQuickActions(tester);
    _expectQuickActionCenters(tester);
    expect(find.text('함께한 장소 보기'), findsOneWidget);
    expect(find.text('한 판 하러 가기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('홈은 320pt·200% 글자에서 빠른 실행을 1열로 재배치한다', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpAccessibleHome(
      tester,
      size: const Size(320, 568),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);

    final homeList = find.byKey(
      const PageStorageKey<String>('dear-home-scroll'),
    );
    await tester.dragUntilVisible(
      find.text('최근 추억'),
      homeList,
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(
      find.text('빠른 실행'),
      homeList,
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(
      find.text('오목'),
      homeList,
      const Offset(0, -320),
    );
    await tester.pumpAndSettle();

    final anniversaryTop = tester.getTopLeft(find.text('기념일')).dy;
    final travelTop = tester.getTopLeft(find.text('여행 지도')).dy;
    final omokTop = tester.getTopLeft(find.text('오목')).dy;

    expect(find.byType(GridView), findsNothing);
    expect(anniversaryTop, lessThan(travelTop));
    expect(travelTop, lessThan(omokTop));
    for (final label in ['기념일', '여행 지도', '오목']) {
      final title = tester.widget<Text>(find.text(label));
      expect(title.maxLines, isNull);
      expect(title.overflow, isNot(TextOverflow.ellipsis));
    }
    expect(find.text('함께한 장소 보기'), findsOneWidget);
    expect(find.text('한 판 하러 가기'), findsOneWidget);
    _expectSingleColumnQuickActions(tester);
    _expectQuickActionCenters(tester);
    _expectQuickActionSemanticsInReadingOrder(tester);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('다크 홈은 카드·텍스트·알림 제어에 dark color scheme을 사용한다', (tester) async {
    final theme = AppTheme.dark();
    final scheme = theme.colorScheme;
    await _pumpAccessibleHome(
      tester,
      size: const Size(375, 812),
      textScale: 1,
      theme: theme,
    );

    final primaryCard = tester.widget<DearCard>(
      find.byKey(const ValueKey('primary-chat-card')),
    );
    final title = tester.widget<Text>(
      find.byKey(const ValueKey('primary-chat-title')),
    );
    final preview = tester.widget<Text>(
      find.byKey(const ValueKey('primary-chat-preview')),
    );
    final notifications = tester.widget<Icon>(
      find.byKey(const ValueKey('home-notifications-icon')),
    );

    expect(primaryCard.color, scheme.surface);
    expect(primaryCard.borderColor, scheme.outlineVariant);
    expect(title.style?.color, scheme.onSurface);
    expect(preview.style?.color, scheme.onSurfaceVariant);
    expect(notifications.color, scheme.onSurface);
    expect(scheme.surface, isNot(DearColors.card));
    expect(scheme.onSurface, isNot(DearColors.ink));
    expect(tester.takeException(), isNull);
  });

  testWidgets('채팅방 헤더는 390x844·200% 글자에서 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const coupleId = '11111111-1111-4111-8111-111111111111';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatCurrentUserIdProvider.overrideWithValue('user-1'),
          coupleNicknameMapProvider.overrideWith(
            (ref, id) => Stream.value(
              const <String, String>{
                'user-1': '하루',
                'user-2': '아주 긴 이름의 상대방',
              },
            ),
          ),
          coupleAvatarUrlMapProvider.overrideWith(
            (ref, id) => Stream.value(const <String, String>{}),
          ),
          anniversaryDateProvider.overrideWith(
            (ref) => Stream.value(DateTime(2024, 1, 1)),
          ),
          chatLatestMessageAtProvider.overrideWith(
            (ref, id) => Stream.value(DateTime.now()),
          ),
          chatPartnerOnlineProvider.overrideWith(
            (ref, id) => Stream.value(true),
          ),
          chatPartnerReadMarkerProvider.overrideWith(
            (ref, id) => Stream.value(null),
          ),
          chatWatchMessagesProvider.overrideWithValue(
            (id) => Stream.value(const <ChatMessage>[]),
          ),
          chatWatchReactionMessageIdsProvider.overrideWithValue(
            (id) => const Stream<int>.empty(),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ChatShellPage(coupleId: coupleId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('아주 긴 이름의 상대방'), findsOneWidget);
    expect(find.text('온라인'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _homeCoupleId = '11111111-1111-4111-8111-111111111111';
const _longChatPreview = '오늘 저녁에 같이 산책하고 돌아오는 길에 오래 이야기하고 싶어';
const _quickActionGlyphs = <String>['anniversary', 'koreaMap', 'omok'];

Future<void> _revealQuickActions(WidgetTester tester) async {
  final homeList = find.byKey(
    const PageStorageKey<String>('dear-home-scroll'),
  );
  await tester.dragUntilVisible(
    find.byKey(const ValueKey('quick-action-omok')),
    homeList,
    const Offset(0, -320),
  );
  await tester.pumpAndSettle();
}

void _expectQuickActionCenters(WidgetTester tester) {
  for (final glyph in _quickActionGlyphs) {
    final tileCenter = tester.getCenter(
      find.byKey(ValueKey('quick-action-$glyph')),
    );
    for (final part in <String>['icon', 'title', 'subtitle']) {
      final partCenter = tester.getCenter(
        find.byKey(ValueKey('quick-action-$glyph-$part')),
      );
      expect(
        (partCenter.dx - tileCenter.dx).abs(),
        lessThanOrEqualTo(1),
        reason: '$glyph $part가 카드의 수평 중앙에 있어야 합니다.',
      );
    }
  }
}

void _expectCompactQuickActionRowsAligned(WidgetTester tester) {
  for (final part in <String>['icon', 'title', 'subtitle']) {
    final referenceY = tester
        .getCenter(find.byKey(ValueKey('quick-action-anniversary-$part')))
        .dy;
    for (final glyph in _quickActionGlyphs.skip(1)) {
      final y = tester
          .getCenter(find.byKey(ValueKey('quick-action-$glyph-$part')))
          .dy;
      expect(
        (y - referenceY).abs(),
        lessThanOrEqualTo(1),
        reason: '3열 카드의 $part 세로 위치가 같아야 합니다.',
      );
    }
  }
}

void _expectSingleColumnQuickActions(WidgetTester tester) {
  final rects = _quickActionGlyphs
      .map((glyph) =>
          tester.getRect(find.byKey(ValueKey('quick-action-$glyph'))))
      .toList(growable: false);

  expect(rects[0].top, lessThan(rects[1].top));
  expect(rects[1].top, lessThan(rects[2].top));
  for (final rect in rects) {
    expect(rect.left, closeTo(20, 0.01));
    expect(rect.width, closeTo(280, 0.01));
    expect(rect.height, greaterThanOrEqualTo(44));
  }

  for (final glyph in _quickActionGlyphs) {
    final title = tester.widget<Text>(
      find.byKey(ValueKey('quick-action-$glyph-title')),
    );
    final subtitle = tester.widget<Text>(
      find.byKey(ValueKey('quick-action-$glyph-subtitle')),
    );
    expect(title.maxLines, isNull);
    expect(title.overflow, isNot(TextOverflow.ellipsis));
    expect(title.textAlign, TextAlign.center);
    expect(subtitle.maxLines, isNull);
    expect(subtitle.overflow, isNot(TextOverflow.ellipsis));
    expect(subtitle.textAlign, TextAlign.center);
  }
}

void _expectQuickActionSemanticsInReadingOrder(WidgetTester tester) {
  final orderedKeys = find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return widget is Semantics &&
            key is ValueKey<String> &&
            _quickActionGlyphs
                .map((glyph) => 'quick-action-$glyph')
                .contains(key.value);
      })
      .evaluate()
      .map((element) => (element.widget.key! as ValueKey<String>).value)
      .toList(growable: false);

  expect(
    orderedKeys,
    const <String>[
      'quick-action-anniversary',
      'quick-action-koreaMap',
      'quick-action-omok',
    ],
  );
  for (final glyph in _quickActionGlyphs) {
    final finder = find.byKey(ValueKey('quick-action-$glyph'));
    final semanticsWidget = tester.widget<Semantics>(finder);
    final semanticsNode = tester.getSemantics(finder);
    expect(semanticsWidget.properties.button, isTrue);
    expect(semanticsWidget.properties.onTap, isNotNull);
    expect(semanticsNode.label, isNotEmpty);
    expect(
      semanticsNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
  }
}

Future<void> _pumpAccessibleHome(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  ThemeData? theme,
  Map<String, String> avatarUrls = const <String, String>{},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final relationshipStart =
      DateUtils.dateOnly(DateTime.now().subtract(const Duration(days: 981)));
  final customItem = AnniversaryItem(
    id: 'custom-1',
    coupleId: _homeCoupleId,
    title: '처음 함께 떠난 여름 여행',
    eventDate: DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 12)),
    ),
    createdAt: DateTime(2026, 1, 1),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myProfileProvider.overrideWith(
          (ref) async => const ProfileInfo(
            userId: 'user-1',
            nickname: '아주 긴 닉네임을 사용하는 사용자',
            pairingCode: 'ABCD',
            coupleId: _homeCoupleId,
            avatarPath: null,
          ),
        ),
        anniversaryDateProvider.overrideWith(
          (ref) => Stream.value(relationshipStart),
        ),
        anniversaryItemsProvider.overrideWith(
          (ref, id) => Stream.value([customItem]),
        ),
        chatUnreadCountProvider.overrideWith(
          (ref, id) => Stream.value(3),
        ),
        chatConversationPreviewProvider.overrideWith(
          (ref, id) => Stream.value(
            ChatConversationPreview(
              text: _longChatPreview,
              createdAt: DateTime.now(),
            ),
          ),
        ),
        notificationInboxProvider.overrideWith(
          (ref, id) => Stream.value(const <NotificationInboxItem>[]),
        ),
        coupleAvatarUrlMapProvider.overrideWith(
          (ref, id) => Stream.value(avatarUrls),
        ),
        coupleNicknameMapProvider.overrideWith(
          (ref, id) => Stream.value(
            const <String, String>{
              'user-1': '하루',
              'user-2': '아주 긴 이름의 상대방',
            },
          ),
        ),
        recentMemoryAlbumPhotosProvider.overrideWith(
          (ref, id) => Stream.value(const <MemoryAlbumPhoto>[]),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const ChatListPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
