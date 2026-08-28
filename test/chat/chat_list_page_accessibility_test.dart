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

  testWidgets('홈은 320pt·200% 글자에서 빠른 실행을 1열로 재배치한다', (tester) async {
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
    expect(tester.takeException(), isNull);
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

Future<void> _pumpAccessibleHome(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  ThemeData? theme,
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
          (ref, id) => Stream.value(const <String, String>{}),
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
