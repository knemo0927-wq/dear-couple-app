import 'dart:async';

import 'package:couple_chat_app/src/common/dear_design.dart';
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

Widget appWithSearch(
  ChatSearchMessages search, {
  double textScale = 1,
  Key? pageKey,
}) {
  return ProviderScope(
    overrides: [
      chatCurrentUserIdProvider.overrideWithValue('user-1'),
      chatSearchMessagesProvider.overrideWithValue(search),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: ChatSearchPage(key: pageKey, coupleId: coupleId),
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
    expect(find.text('찾고 싶은 대화를 입력해 주세요'), findsOneWidget);
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
      }, pageKey: const ValueKey('blocking-error-search')),
    );
    await tester.enterText(find.byType(SearchBar), '찾은');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    expect(find.byType(DearInlineError), findsNothing);
    expect(find.widgetWithText(FilledButton, '다시 시도'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('1개의 결과 · 1번째'), findsOneWidget);
  });

  testWidgets('새 검색의 로딩·오류·재시도 동안 마지막 결과와 선택을 보존한다', (tester) async {
    final semantics = tester.ensureSemantics();
    final firstSeaAttempt = Completer<List<ChatMessage>>();
    final seaRetry = Completer<List<ChatMessage>>();
    var seaAttempts = 0;

    await tester.pumpWidget(
      appWithSearch(({
        required String coupleId,
        required String query,
        int limit = 100,
      }) {
        if (query == '여행') {
          return Future.value([
            message(10, '첫 여행 기록'),
            message(11, '두 번째 여행 기록'),
          ]);
        }
        seaAttempts++;
        return seaAttempts == 1 ? firstSeaAttempt.future : seaRetry.future;
      }),
    );

    await tester.enterText(find.byType(SearchBar), '여행');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('다음 검색 결과'));
    await tester.pumpAndSettle();
    expect(find.text('2개의 결과 · 2번째'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), '바다');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.pump();

    expect(find.byType(DearInlineLoading), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-result-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-result-11')), findsOneWidget);
    expect(find.text('“여행” 결과 2개 · 2번째'), findsOneWidget);
    expect(
      find.text('현재 “바다” 검색 중 · “여행” 이전 결과 표시'),
      findsOneWidget,
    );
    final loadingSemantics = tester.getSemantics(
      find.byKey(const Key('chat-search-inline-loading')),
    );
    final preservedSemantics = tester.getSemantics(
      find.byKey(const Key('chat-search-preserved-query')),
    );
    expect(loadingSemantics.label, contains('바다'));
    expect(loadingSemantics.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue);
    expect(preservedSemantics.label, contains('여행 이전 검색 결과'));
    expect(preservedSemantics.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue);

    firstSeaAttempt.completeError(Exception('network failed'));
    await tester.pumpAndSettle();

    expect(find.byType(DearInlineError), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-result-11')), findsOneWidget);
    expect(find.text('“여행” 결과 2개 · 2번째'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '다시 시도'));
    await tester.pump();
    expect(find.byType(DearInlineError), findsOneWidget);
    expect(find.text('다시 불러오는 중'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-result-11')), findsOneWidget);

    seaRetry.complete([message(20, '바다에서 다시 찾은 기록')]);
    await tester.pumpAndSettle();

    expect(find.byType(DearInlineError), findsNothing);
    expect(find.byKey(const Key('chat-search-preserved-query')), findsNothing);
    expect(find.byKey(const ValueKey('chat-search-result-10')), findsNothing);
    expect(find.byKey(const ValueKey('chat-search-result-20')), findsOneWidget);
    expect(find.text('1개의 결과 · 1번째'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('generation은 동일 검색어 재요청과 A→B→A의 오래된 응답을 폐기한다', (tester) async {
    final controlled = _ControlledSearch();
    await tester.pumpWidget(appWithSearch(controlled.call));

    await tester.enterText(find.byType(SearchBar), '여행');
    await tester.pump(const Duration(milliseconds: 310));
    expect(controlled.calls, hasLength(1));

    tester.widget<SearchBar>(find.byType(SearchBar)).onSubmitted!.call('여행');
    await tester.pump();
    expect(controlled.calls, hasLength(2));

    controlled.calls[1].complete([message(2, '두 번째 여행 응답')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-search-result-2')), findsOneWidget);

    controlled.calls[0].complete([message(1, '오래된 첫 여행 응답')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-search-result-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-result-1')), findsNothing);

    await tester.enterText(find.byType(SearchBar), '바다');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.enterText(find.byType(SearchBar), '여행');
    await tester.pump(const Duration(milliseconds: 310));
    expect(controlled.calls, hasLength(4));

    controlled.calls[3].complete([message(4, '마지막 여행 응답')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-search-result-4')), findsOneWidget);

    controlled.calls[2].complete([message(3, '늦게 도착한 바다 응답')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-search-result-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-result-3')), findsNothing);
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

class _ControlledSearch {
  final List<_PendingSearchCall> calls = <_PendingSearchCall>[];

  Future<List<ChatMessage>> call({
    required String coupleId,
    required String query,
    int limit = 100,
  }) {
    final pending = _PendingSearchCall(query);
    calls.add(pending);
    return pending.future;
  }
}

class _PendingSearchCall {
  _PendingSearchCall(this.query);

  final String query;
  final Completer<List<ChatMessage>> _completer =
      Completer<List<ChatMessage>>();

  Future<List<ChatMessage>> get future => _completer.future;

  void complete(List<ChatMessage> messages) => _completer.complete(messages);
}
