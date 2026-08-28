import 'dart:async';

import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_media_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const coupleId = '11111111-1111-4111-8111-111111111111';

ChatMessage photoMessage(int id) => ChatMessage(
      id: id,
      coupleId: coupleId,
      senderId: 'user-2',
      body: null,
      imagePath: 'couple/photo-$id.jpg',
      createdAt: DateTime(2026, 7, 12, 9, id),
      heartCount: 0,
      isHeartedByMe: false,
    );

Widget mediaApp(
  ChatFetchMediaPage fetch, {
  ChatResolveImageUrl? resolveUrl,
}) {
  return ProviderScope(
    overrides: [
      chatFetchMediaPageProvider.overrideWithValue(fetch),
      chatResolveImageUrlProvider.overrideWithValue(
        resolveUrl ?? (path) async => 'https://example.invalid/$path',
      ),
    ],
    child: MaterialApp(
      home: ChatMediaPage(key: UniqueKey(), coupleId: coupleId),
    ),
  );
}

void main() {
  testWidgets('초기 로딩 후 사진 그리드와 페이지 결과를 표시한다', (tester) async {
    final completer = Completer<ChatMessagePage>();
    await tester.pumpWidget(
      mediaApp(({
        required String coupleId,
        int? beforeMessageId,
        int limit = 30,
      }) =>
          completer.future),
    );
    await tester.pump();
    expect(find.byKey(const Key('chat-media-loading')), findsOneWidget);

    completer.complete(
      ChatMessagePage(
        messages: [photoMessage(2), photoMessage(1)],
        hasMore: false,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('chat-media-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-media-1')), findsOneWidget);
    expect(find.text('모든 사진을 불러왔어요.'), findsOneWidget);
  });

  testWidgets('빈 결과를 구분하고 초기 오류 재시도는 busy 상태를 노출한다', (tester) async {
    await tester.pumpWidget(
      mediaApp(({
        required String coupleId,
        int? beforeMessageId,
        int limit = 30,
      }) async =>
          const ChatMessagePage(messages: [], hasMore: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('아직 주고받은 사진이 없어요'), findsOneWidget);

    var attempts = 0;
    final retry = Completer<ChatMessagePage>();
    await tester.pumpWidget(
      mediaApp(({
        required String coupleId,
        int? beforeMessageId,
        int limit = 30,
      }) {
        attempts += 1;
        if (attempts == 1) {
          return Future<ChatMessagePage>.error(Exception('network failed'));
        }
        return retry.future;
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-media-initial-error')), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '다시 시도'));
    await tester.pump();
    expect(find.text('다시 불러오는 중'), findsOneWidget);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);

    retry.complete(
      ChatMessagePage(messages: [photoMessage(1)], hasMore: false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('chat-media-1')), findsOneWidget);
  });

  testWidgets('새로고침은 기존 그리드를 유지하고 성공 시 ID를 중복 없이 교체한다', (tester) async {
    var calls = 0;
    final refresh = Completer<ChatMessagePage>();
    await tester.pumpWidget(
      mediaApp(({
        required String coupleId,
        int? beforeMessageId,
        int limit = 30,
      }) {
        calls += 1;
        if (calls == 1) {
          return Future.value(
            ChatMessagePage(
              messages: [photoMessage(3), photoMessage(2)],
              hasMore: false,
            ),
          );
        }
        return refresh.future;
      }),
    );
    await tester.pumpAndSettle();

    final refreshFuture = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('chat-media-refresh-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-media-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-media-2')), findsOneWidget);
    expect(find.text('모든 사진을 불러왔어요.'), findsOneWidget);

    refresh.complete(
      ChatMessagePage(
        messages: [photoMessage(2), photoMessage(2), photoMessage(1)],
        hasMore: false,
      ),
    );
    await refreshFuture;
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-media-3')), findsNothing);
    expect(find.byKey(const ValueKey('chat-media-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-media-1')), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('빈 상태 새로고침 오류는 내용 위에 남고 재시도 중에도 비우지 않는다', (tester) async {
    var calls = 0;
    final failedRefresh = Completer<ChatMessagePage>();
    final retry = Completer<ChatMessagePage>();
    await tester.pumpWidget(
      mediaApp(({
        required String coupleId,
        int? beforeMessageId,
        int limit = 30,
      }) {
        calls += 1;
        if (calls == 1) {
          return Future.value(
            const ChatMessagePage(messages: [], hasMore: false),
          );
        }
        if (calls == 2) return failedRefresh.future;
        return retry.future;
      }),
    );
    await tester.pumpAndSettle();

    final refreshFuture = tester
        .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
        .show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('chat-media-refresh-loading')), findsOneWidget);
    expect(find.byKey(const Key('chat-media-empty')), findsOneWidget);

    failedRefresh.completeError(Exception('refresh failed'));
    await refreshFuture;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-media-refresh-error')), findsOneWidget);
    expect(find.byKey(const Key('chat-media-empty')), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '다시 시도'));
    await tester.pump();
    expect(find.byKey(const Key('chat-media-refresh-error')), findsOneWidget);
    expect(find.byKey(const Key('chat-media-empty')), findsOneWidget);
    expect(find.text('다시 불러오는 중'), findsOneWidget);
    expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed, isNull);

    retry.complete(
      ChatMessagePage(messages: [photoMessage(4)], hasMore: false),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-media-4')), findsOneWidget);
    expect(find.byKey(const Key('chat-media-refresh-error')), findsNothing);
  });

  testWidgets('더 불러오기 오류는 footer에 남고 스크롤 자동 재호출을 막는다', (tester) async {
    var calls = 0;
    final retry = Completer<ChatMessagePage>();
    final initialMessages = [
      for (var id = 30; id >= 19; id -= 1) photoMessage(id),
    ];
    await tester.pumpWidget(
      mediaApp(
        ({
          required String coupleId,
          int? beforeMessageId,
          int limit = 30,
        }) {
          calls += 1;
          if (calls == 1) {
            return Future.value(
              ChatMessagePage(messages: initialMessages, hasMore: true),
            );
          }
          if (calls == 2) {
            return Future<ChatMessagePage>.error(Exception('load more failed'));
          }
          return retry.future;
        },
        resolveUrl: (_) => Future.error(Exception('signed url failed')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat-media-load-more-error')), findsOneWidget);
    expect(calls, 2);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(calls, 2);

    final retryButton = find.descendant(
      of: find.byKey(const Key('chat-media-load-more-error')),
      matching: find.widgetWithText(TextButton, '다시 시도'),
    );
    await tester.tap(retryButton);
    await tester.pump();
    expect(find.text('다시 불러오는 중'), findsOneWidget);
    expect(calls, 3);

    retry.complete(
      ChatMessagePage(
        messages: [photoMessage(19), photoMessage(18), photoMessage(18)],
        hasMore: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-media-19')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-media-18')), findsOneWidget);
    expect(find.byKey(const Key('chat-media-load-more-error')), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('모든 사진을 불러왔어요.'), findsOneWidget);
  });

  testWidgets('서명 URL과 네트워크 이미지 실패는 정확한 재시도 button semantics를 노출한다',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    var resolveAttempts = 0;

    await tester.pumpWidget(
      mediaApp(
        ({
          required String coupleId,
          int? beforeMessageId,
          int limit = 30,
        }) async =>
            ChatMessagePage(messages: [photoMessage(7)], hasMore: false),
        resolveUrl: (_) async {
          resolveAttempts += 1;
          if (resolveAttempts == 1) throw Exception('signed URL failed');
          return 'https://example.invalid/photo-7-$resolveAttempts.jpg';
        },
      ),
    );
    await tester.pumpAndSettle();

    var retryFinder = find.byKey(const ValueKey('chat-media-image-retry-7'));
    var retryNode = tester.getSemantics(retryFinder);
    expect(retryNode.label, '사진 다시 불러오기');
    expect(
      retryNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.widget<Semantics>(retryFinder).properties.button, isTrue);
    expect(tester.getSize(retryFinder).height, greaterThanOrEqualTo(44));

    await tester.tap(retryFinder);
    await tester.pumpAndSettle();
    expect(resolveAttempts, 2);
    expect(
      find.byKey(const ValueKey('chat-media-network-image-7-1')),
      findsOneWidget,
    );

    retryFinder = find.byKey(const ValueKey('chat-media-image-retry-7'));
    retryNode = tester.getSemantics(retryFinder);
    expect(retryNode.label, '사진 다시 불러오기');
    expect(
      retryNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(retryFinder);
    await tester.pumpAndSettle();
    expect(resolveAttempts, 3);
    expect(
      find.byKey(const ValueKey('chat-media-network-image-7-2')),
      findsOneWidget,
    );

    semantics.dispose();
  });
}
