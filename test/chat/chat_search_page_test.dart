import 'dart:async';

import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const coupleId = '11111111-1111-4111-8111-111111111111';

ChatMessage message(int id, String body) => ChatMessage(
      id: id,
      coupleId: coupleId,
      senderId: id.isEven ? 'user-1' : 'user-2',
      body: body,
      imagePath: null,
      createdAt: DateTime(2026, 7, 12, 9, id),
      heartCount: 0,
      isHeartedByMe: false,
    );

Widget appWithSearch(ChatSearchMessages search, {double textScale = 1}) {
  return ProviderScope(
    overrides: [
      chatCurrentUserIdProvider.overrideWithValue('user-1'),
      chatSearchMessagesProvider.overrideWithValue(search),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const ChatSearchPage(coupleId: coupleId),
      ),
    ),
  );
}

void main() {
  testWidgets('검색 결과를 강조하고 이전·다음 결과로 탐색한다', (tester) async {
    await tester.pumpWidget(
      appWithSearch(({
        required String coupleId,
        required String query,
        int limit = 100,
      }) async {
        return [message(3, '여름 여행을 기억해'), message(2, '다음 여행 계획')];
      }),
    );

    await tester.enterText(find.byType(SearchBar), '여행');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();

    expect(find.text('2개의 결과 · 1번째'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-result-3')), findsOneWidget);

    await tester.tap(find.byTooltip('다음 검색 결과'));
    await tester.pumpAndSettle();

    expect(find.text('2개의 결과 · 2번째'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-result-2')), findsOneWidget);
  });

  testWidgets('검색 로딩·빈 결과·오류 재시도 상태를 구분한다', (tester) async {
    final completer = Completer<List<ChatMessage>>();
    await tester.pumpWidget(
      appWithSearch(({
        required String coupleId,
        required String query,
        int limit = 100,
      }) =>
          completer.future),
    );
    await tester.enterText(find.byType(SearchBar), '없는 말');
    await tester.pump(const Duration(milliseconds: 310));
    expect(find.text('대화를 찾고 있어요...'), findsOneWidget);
    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('검색 결과가 없어요'), findsOneWidget);

    var attempts = 0;
    await tester.pumpWidget(
      appWithSearch(({
        required String coupleId,
        required String query,
        int limit = 100,
      }) async {
        attempts++;
        if (attempts == 1) throw Exception('network failed');
        return [message(1, '다시 찾은 말')];
      }),
    );
    await tester.enterText(find.byType(SearchBar), '찾은');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('1개의 결과 · 1번째'), findsOneWidget);
  });

  testWidgets('큰 글자에서도 검색 결과 화면이 오버플로 없이 스크롤된다', (tester) async {
    await tester.pumpWidget(
      appWithSearch(
          ({
            required String coupleId,
            required String query,
            int limit = 100,
          }) async =>
              [message(1, '큰 글자로 보는 여행 검색 결과입니다.')],
          textScale: 2),
    );
    await tester.enterText(find.byType(SearchBar), '여행');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('chat-search-result-1')), findsOneWidget);
  });
}
