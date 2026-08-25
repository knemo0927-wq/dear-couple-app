import 'dart:async';

import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_media_page.dart';
import 'package:flutter/material.dart';
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

Widget mediaApp(ChatFetchMediaPage fetch) {
  return ProviderScope(
    overrides: [
      chatFetchMediaPageProvider.overrideWithValue(fetch),
      chatResolveImageUrlProvider.overrideWithValue(
        (path) async => 'https://example.invalid/$path',
      ),
    ],
    child: MaterialApp(
      home: ChatMediaPage(key: UniqueKey(), coupleId: coupleId),
    ),
  );
}

void main() {
  testWidgets('사진 모아보기는 로딩 후 사진 그리드와 페이지 결과를 표시한다', (tester) async {
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
          messages: [photoMessage(2), photoMessage(1)], hasMore: false),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('chat-media-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-media-1')), findsOneWidget);
    expect(find.text('모든 사진을 불러왔어요.'), findsOneWidget);
  });

  testWidgets('사진이 없을 때 안내하고 오류에서는 다시 시도한다', (tester) async {
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
    await tester.pumpWidget(
      mediaApp(({
        required String coupleId,
        int? beforeMessageId,
        int limit = 30,
      }) async {
        attempts++;
        if (attempts == 1) throw Exception('network failed');
        return ChatMessagePage(messages: [photoMessage(1)], hasMore: false);
      }),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '다시 시도'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('chat-media-1')), findsOneWidget);
  });
}
