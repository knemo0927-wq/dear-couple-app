import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_inbox.dart';
import 'package:couple_chat_app/src/features/notifications/presentation/notification_inbox_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('읽음 저장이 실패해도 선택한 알림 딥링크를 연다', (tester) async {
    const coupleId = '11111111-1111-4111-8111-111111111111';
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationInboxPage(),
        ),
        GoRoute(
          path: '/chat/:coupleId',
          builder: (_, __) => const Scaffold(body: Text('chat-detail')),
        ),
      ],
    );
    addTearDown(router.dispose);

    final session = Session(
      accessToken: 'test-token',
      tokenType: 'bearer',
      user: const User(
        id: 'user-1',
        appMetadata: <String, dynamic>{},
        userMetadata: <String, dynamic>{},
        aud: 'authenticated',
        createdAt: '2026-07-12T00:00:00Z',
      ),
    );
    final item = NotificationInboxItem(
      id: '22222222-2222-4222-8222-222222222222',
      category: 'message',
      route: '/chat/$coupleId',
      payload: const <String, dynamic>{
        'title': '새 메시지',
        'body': '상대방이 메시지를 보냈어요.',
      },
      status: 'sent',
      createdAt: DateTime.utc(2026, 7, 12),
      readAt: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith((ref) => Stream.value(session)),
          notificationInboxProvider.overrideWith(
            (ref, userId) => Stream.value([item]),
          ),
          markNotificationReadProvider.overrideWithValue((ids) async {
            throw Exception('offline');
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 메시지'));
    await tester.pumpAndSettle();

    expect(find.text('chat-detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('다크 모드의 읽음·안 읽음 카드와 텍스트가 semantic 색을 사용한다', (tester) async {
    final theme = AppTheme.dark();
    final session = Session(
      accessToken: 'test-token',
      tokenType: 'bearer',
      user: const User(
        id: 'user-1',
        appMetadata: <String, dynamic>{},
        userMetadata: <String, dynamic>{},
        aud: 'authenticated',
        createdAt: '2026-07-12T00:00:00Z',
      ),
    );
    final createdAt = DateTime.now().subtract(const Duration(minutes: 5));
    final items = [
      NotificationInboxItem(
        id: 'unread',
        category: 'message',
        route: '/notifications',
        payload: const <String, dynamic>{
          'title': '안 읽은 알림',
          'body': '확인할 소식이 있어요.',
        },
        status: 'sent',
        createdAt: createdAt,
        readAt: null,
      ),
      NotificationInboxItem(
        id: 'read',
        category: 'message',
        route: '/notifications',
        payload: const <String, dynamic>{
          'title': '읽은 알림',
          'body': '이미 확인한 소식이에요.',
        },
        status: 'sent',
        createdAt: createdAt,
        readAt: createdAt,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith((ref) => Stream.value(session)),
          notificationInboxProvider.overrideWith(
            (ref, userId) => Stream.value(items),
          ),
          markNotificationReadProvider.overrideWithValue((ids) async {}),
        ],
        child: MaterialApp(
          theme: theme,
          home: const NotificationInboxPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final unreadCard = tester.widget<DearCard>(
      find.byKey(const ValueKey('notification-inbox-unread')),
    );
    final readCard = tester.widget<DearCard>(
      find.byKey(const ValueKey('notification-inbox-read')),
    );
    expect(unreadCard.color, theme.colorScheme.primaryContainer);
    expect(readCard.color, theme.colorScheme.surface);
    expect(
      tester.widget<Text>(find.text('안 읽은 알림')).style?.color,
      theme.colorScheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('확인할 소식이 있어요.')).style?.color,
      theme.colorScheme.onSurfaceVariant,
    );
    expect(tester.takeException(), isNull);
  });
}
