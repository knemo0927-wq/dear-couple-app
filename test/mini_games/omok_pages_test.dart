import 'dart:async';
import 'dart:io';

import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_providers.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_repository.dart';
import 'package:couple_chat_app/src/features/mini_games/presentation/mini_games_page.dart';
import 'package:couple_chat_app/src/features/mini_games/presentation/omok_game_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const profile = ProfileInfo(
    userId: 'user-1',
    nickname: '하루',
    pairingCode: 'ABCD',
    coupleId: 'couple-1',
    avatarPath: null,
  );

  final finishedGame = OmokRecentGame(
    sessionId: 'finished-1',
    status: 'black_win',
    result: 'win',
    endReason: 'five_in_a_row',
    winnerUserId: 'user-1',
    finishedAt: DateTime(2026, 7, 12, 19, 30),
    createdAt: DateTime(2026, 7, 12, 19),
  );

  void configurePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  List<Override> dashboardOverrides({OmokInviteState? outgoingInvite}) => [
        myProfileProvider.overrideWith((ref) async => profile),
        latestOutgoingOmokInviteProvider.overrideWith(
          (ref, userId) => Stream.value(outgoingInvite),
        ),
        omokRecordProvider.overrideWith(
          (ref, args) async => const OmokRecord(
            wins: 7,
            losses: 3,
            draws: 1,
            totalGames: 11,
          ),
        ),
        omokRecentGamesProvider.overrideWith(
          (ref, args) async => [finishedGame],
        ),
        omokAllGamesProvider.overrideWith(
          (ref, args) async => [finishedGame],
        ),
        latestOmokActivityAtProvider.overrideWith(
          (ref, coupleId) => const Stream<DateTime?>.empty(),
        ),
        rematchNotificationsProvider.overrideWith(
          (ref, userId) => const Stream<List<OmokNotification>>.empty(),
        ),
      ];

  GoRouter dashboardRouter() => GoRouter(
        initialLocation: '/mini-games',
        routes: [
          GoRoute(
            path: '/mini-games',
            builder: (_, __) => const MiniGamesPage(),
          ),
          GoRoute(
            path: '/chat-list',
            builder: (_, __) => const Scaffold(body: Text('채팅')),
          ),
          GoRoute(
            path: '/omok/:sessionId',
            builder: (_, state) => Scaffold(
              body: Text('game-${state.pathParameters['sessionId']}'),
            ),
          ),
          GoRoute(
            path: '/omok-wait/:inviteId',
            builder: (_, state) => Scaffold(
              body: Text('wait-${state.pathParameters['inviteId']}'),
            ),
          ),
        ],
      );

  OmokSessionInfo gameSession({
    String currentTurnUserId = 'user-1',
    String status = 'playing',
    String? winnerUserId,
  }) {
    return OmokSessionInfo(
      id: 'accessible-game',
      coupleId: 'couple-1',
      blackUserId: 'user-1',
      whiteUserId: 'user-2',
      currentTurnUserId: status == 'playing' ? currentTurnUserId : null,
      status: status,
      winnerUserId: winnerUserId,
      turnExpiresAt: status == 'playing'
          ? DateTime.now().add(const Duration(minutes: 5))
          : null,
      createdAt: DateTime.now(),
    );
  }

  Future<void> pumpAccessibleGame(
    WidgetTester tester, {
    required Stream<OmokSessionInfo?> sessionStream,
    required Stream<List<OmokMove>> movesStream,
    PlaceOmokMoveAction? placeMove,
    Size size = const Size(390, 844),
    double textScale = 1,
    double bottomInset = 0,
    bool disableAnimations = false,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final effectivePlaceMove = placeMove ??
        ({required sessionId, required x, required y}) async =>
            const OmokMoveResult(
              status: 'playing',
              nextTurnUserId: 'user-2',
              winnerUserId: null,
              turnExpiresAt: null,
            );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          omokSessionProvider.overrideWith(
            (ref, sessionId) => sessionStream,
          ),
          omokMovesProvider.overrideWith(
            (ref, sessionId) => movesStream,
          ),
          placeOmokMoveProvider.overrideWithValue(effectivePlaceMove),
          rematchNotificationsProvider.overrideWith(
            (ref, userId) => const Stream<List<OmokNotification>>.empty(),
          ),
        ],
        child: MaterialApp(
          theme: theme,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(textScale),
                padding: EdgeInsets.only(bottom: bottomInset),
                viewPadding: EdgeInsets.only(bottom: bottomInset),
                disableAnimations: disableAnimations,
              ),
              child: child!,
            );
          },
          home: const OmokGamePage(sessionId: 'accessible-game'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectCoordinate(
    WidgetTester tester,
    Key dropdownKey,
    int value,
  ) async {
    await tester.tap(find.byKey(dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$value').last);
    await tester.pumpAndSettle();
  }

  testWidgets('메인 더보기가 규칙·전체 기록·새로고침 액션을 제공한다', (tester) async {
    configurePhone(tester);
    final router = dashboardRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: dashboardOverrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('omok-main-overflow')));
    await tester.pumpAndSettle();

    expect(find.text('전체 대국 기록'), findsOneWidget);
    expect(find.text('오목 규칙'), findsOneWidget);
    expect(find.text('새로고침'), findsOneWidget);

    await tester.tap(find.text('오목 규칙'));
    await tester.pumpAndSettle();
    expect(find.text('가로·세로·대각선 중 한 방향으로 돌 5개를 먼저 이으면 승리해요.'), findsOneWidget);
  });

  testWidgets('전체 전적과 최근 경기 더보기가 실제 전체 기록 화면을 연다', (tester) async {
    configurePhone(tester);
    final router = dashboardRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: dashboardOverrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('omok-record-history-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('전체 대국 기록'), findsOneWidget);
    expect(find.text('총 1판'), findsOneWidget);
    expect(find.text('승리'), findsWidgets);
    expect(find.byIcon(Icons.emoji_events_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('뒤로가기').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('omok-recent-history-button')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('omok-recent-history-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('전체 대국 기록'), findsOneWidget);
  });

  testWidgets('재진입 시 서버 Realtime의 최근 발신 초대 대기 상태를 복원한다', (tester) async {
    configurePhone(tester);
    final router = dashboardRouter();
    addTearDown(router.dispose);
    final restoredInvite = OmokInviteState(
      id: 'restored-invite',
      status: 'open',
      sessionId: null,
      expiresAt: DateTime.now().add(const Duration(minutes: 3)),
      inviteType: 'push',
      senderUserId: 'user-1',
      recipientUserId: 'user-2',
      createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: dashboardOverrides(outgoingInvite: restoredInvite),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('전송 완료 · 상대 응답 대기 중'), findsOneWidget);
    expect(find.text('대기실 보기'), findsOneWidget);
    expect(find.text('상대 응답 대기 중'), findsOneWidget);
  });

  testWidgets('메인 오목 화면은 390pt·200% 큰 글자에서 레이아웃이 넘치지 않는다', (tester) async {
    configurePhone(tester);
    final router = dashboardRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: dashboardOverrides(),
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('다크 모드의 메인·기록·규칙이 semantic 색을 사용한다', (tester) async {
    configurePhone(tester);
    final router = dashboardRouter();
    addTearDown(router.dispose);
    final theme = AppTheme.dark();

    await tester.pumpWidget(
      ProviderScope(
        overrides: dashboardOverrides(),
        child: MaterialApp.router(
          theme: theme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DearIconBubble>(find.byType(DearIconBubble).first)
          .background,
      theme.colorScheme.surface,
    );
    expect(
      tester.widget<Text>(find.text('한 판 신청하기')).style?.color,
      theme.colorScheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('우리, 지금 한 판 어때요?')).style?.color,
      theme.colorScheme.onSurfaceVariant,
    );
    final dashboardResult = tester.widget<Container>(
      find.byKey(const ValueKey('omok-result-finished-1')),
    );
    final dashboardResultDecoration =
        dashboardResult.decoration! as BoxDecoration;
    expect(
      dashboardResultDecoration.color,
      theme.colorScheme.tertiaryContainer,
    );

    await tester.tap(find.byKey(const ValueKey('omok-main-overflow')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('오목 규칙'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('오목 규칙')).style?.color,
      theme.colorScheme.onSurface,
    );
    final ruleBadge = tester.widget<Container>(
      find.byKey(const ValueKey('omok-rule-number-1')),
    );
    expect(
      (ruleBadge.decoration! as BoxDecoration).color,
      theme.colorScheme.primaryContainer,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('omok-rule-number-1')),
              matching: find.text('1'),
            ),
          )
          .style
          ?.color,
      theme.colorScheme.onPrimaryContainer,
    );

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('omok-record-history-button')),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('대국 히스토리')).style?.color,
      theme.colorScheme.onSurface,
    );
    final historyResult = tester.widget<Container>(
      find.byKey(const ValueKey('omok-result-finished-1')),
    );
    final historyDecoration = historyResult.decoration! as BoxDecoration;
    expect(historyDecoration.color, theme.colorScheme.tertiaryContainer);
    expect((historyDecoration.border! as Border).top.color,
        theme.colorScheme.tertiary);
    expect(tester.takeException(), isNull);
  });

  testWidgets('대국은 실시간 연결·보드 요약을 알리고 1초 타이머로 서버를 폴링하지 않는다', (tester) async {
    configurePhone(tester);
    var syncCalls = 0;
    final session = OmokSessionInfo(
      id: 'game-1',
      coupleId: 'couple-1',
      blackUserId: 'user-1',
      whiteUserId: 'user-2',
      currentTurnUserId: 'user-1',
      status: 'playing',
      winnerUserId: null,
      turnExpiresAt: DateTime.now().add(const Duration(seconds: 30)),
      createdAt: DateTime.now(),
    );
    final moves = [
      OmokMove(
        id: 1,
        sessionId: 'game-1',
        moveNo: 1,
        userId: 'user-1',
        stone: 'black',
        x: 7,
        y: 7,
        createdAt: DateTime.now(),
      ),
    ];
    final router = GoRouter(
      initialLocation: '/omok/game-1',
      routes: [
        GoRoute(
          path: '/omok/:sessionId',
          builder: (_, state) => OmokGamePage(
            sessionId: state.pathParameters['sessionId']!,
          ),
        ),
        GoRoute(
          path: '/mini-games',
          builder: (_, __) => const Scaffold(body: Text('미니게임')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          omokSessionProvider.overrideWith(
            (ref, sessionId) => Stream.value(session),
          ),
          omokMovesProvider.overrideWith(
            (ref, sessionId) => Stream.value(moves),
          ),
          rematchNotificationsProvider.overrideWith(
            (ref, userId) => const Stream<List<OmokNotification>>.empty(),
          ),
          syncOmokTurnProvider.overrideWithValue((sessionId) async {
            syncCalls += 1;
            return OmokTurnSync(
              status: 'playing',
              winnerUserId: null,
              currentTurnUserId: 'user-1',
              turnExpiresAt: session.turnExpiresAt,
              secondsLeft: 27,
            );
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('실시간 연결됨'), findsOneWidget);
    expect(find.text('내 차례'), findsOneWidget);
    final boardSemantics = tester.getSemantics(
      find.byKey(const ValueKey('omok-board-summary')),
    );
    expect(boardSemantics.label, '오목판 요약');
    expect(boardSemantics.value, contains('흑돌 1개'));
    expect(boardSemantics.value, contains('8행 8열'));

    await tester.pump(const Duration(seconds: 3));
    expect(syncCalls, 0);

    await tester.tap(find.byKey(const ValueKey('omok-game-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('기권하기'), findsOneWidget);
    expect(find.text('오목 규칙'), findsOneWidget);
    expect(find.text('재대결 신청'), findsNothing);
  });

  testWidgets('작은 보드 셀 탭은 좌표 확인을 열고 명시적 확인 뒤 정확한 좌표를 호출한다', (tester) async {
    final placement = Completer<OmokMoveResult>();
    var placeCalls = 0;
    String? capturedSessionId;
    int? capturedX;
    int? capturedY;

    await pumpAccessibleGame(
      tester,
      sessionStream: Stream.value(gameSession()),
      movesStream: Stream.value(const <OmokMove>[]),
      placeMove: ({required sessionId, required x, required y}) {
        placeCalls += 1;
        capturedSessionId = sessionId;
        capturedX = x;
        capturedY = y;
        return placement.future;
      },
    );

    final coordinateButton =
        find.byKey(const ValueKey('omok-coordinate-place-button'));
    expect(coordinateButton, findsOneWidget);
    expect(tester.getSize(coordinateButton).height, greaterThanOrEqualTo(48));
    expect(
      find.byKey(const ValueKey('omok-board-interactive-viewer')),
      findsOneWidget,
    );
    final boardSummary = tester.getSemantics(
      find.byKey(const ValueKey('omok-board-summary')),
    );
    expect(boardSummary.hint, contains('확대하거나 이동'));
    expect(boardSummary.hint, contains('좌표로 돌 놓기'));

    await tester.tap(
      find.byKey(
        const ValueKey('omok-board-cell-row-4-column-6'),
      ),
    );
    await tester.pumpAndSettle();

    expect(placeCalls, 0);
    expect(find.byKey(const ValueKey('omok-coordinate-sheet')), findsOneWidget);
    expect(find.text('행'), findsOneWidget);
    expect(find.text('열'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<int>>(
            find.descendant(
              of: find.byKey(const ValueKey('omok-coordinate-row')),
              matching: find.byType(DropdownButton<int>),
            ),
          )
          .items,
      hasLength(15),
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('omok-coordinate-status')),
          )
          .label,
      allOf(contains('4행 6열은 빈칸'), contains('현재 내 차례')),
    );

    final confirm = find.byKey(const ValueKey('omok-coordinate-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pump();

    expect(placeCalls, 1);
    expect(capturedSessionId, 'accessible-game');
    expect(capturedX, 5);
    expect(capturedY, 3);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(
      find.descendant(of: confirm, matching: find.text('돌 놓는 중...')),
      findsOneWidget,
    );

    placement.complete(
      const OmokMoveResult(
        status: 'playing',
        nextTurnUserId: 'user-2',
        winnerUserId: null,
        turnExpiresAt: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('omok-coordinate-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택 좌표의 흑돌·백돌을 live 안내하고 occupied 확인을 비활성화한다', (tester) async {
    final moves = [
      OmokMove(
        id: 1,
        sessionId: 'accessible-game',
        moveNo: 1,
        userId: 'user-1',
        stone: 'black',
        x: 7,
        y: 7,
        createdAt: DateTime.now(),
      ),
      OmokMove(
        id: 2,
        sessionId: 'accessible-game',
        moveNo: 2,
        userId: 'user-2',
        stone: 'white',
        x: 4,
        y: 4,
        createdAt: DateTime.now(),
      ),
    ];
    var placeCalls = 0;

    await pumpAccessibleGame(
      tester,
      sessionStream: Stream.value(gameSession()),
      movesStream: Stream.value(moves),
      placeMove: ({required sessionId, required x, required y}) async {
        placeCalls += 1;
        return const OmokMoveResult(
          status: 'playing',
          nextTurnUserId: 'user-2',
          winnerUserId: null,
          turnExpiresAt: null,
        );
      },
    );

    await tester.tap(
      find.byKey(const ValueKey('omok-coordinate-place-button')),
    );
    await tester.pumpAndSettle();

    Finder status() => find.byKey(const ValueKey('omok-coordinate-status'));
    final confirm = find.byKey(const ValueKey('omok-coordinate-confirm'));
    expect(tester.getSemantics(status()).label, contains('8행 8열은 흑돌'));
    expect(
      tester
          .getSemantics(status())
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await selectCoordinate(
      tester,
      const ValueKey('omok-coordinate-row'),
      5,
    );
    await selectCoordinate(
      tester,
      const ValueKey('omok-coordinate-column'),
      5,
    );

    expect(tester.getSemantics(status()).label, contains('5행 5열은 백돌'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(placeCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('열린 좌표 시트가 상대 차례와 종료 이유를 실시간 안내하고 확인을 막는다', (tester) async {
    final sessions = StreamController<OmokSessionInfo?>.broadcast();
    final moves = StreamController<List<OmokMove>>.broadcast();
    addTearDown(sessions.close);
    addTearDown(moves.close);

    await pumpAccessibleGame(
      tester,
      sessionStream: sessions.stream,
      movesStream: moves.stream,
    );
    sessions.add(gameSession());
    moves.add(const <OmokMove>[]);
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('omok-coordinate-place-button')),
    );
    await tester.pumpAndSettle();

    final status = find.byKey(const ValueKey('omok-coordinate-status'));
    final confirm = find.byKey(const ValueKey('omok-coordinate-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    sessions.add(gameSession(currentTurnUserId: 'user-2'));
    await tester.pump();
    await tester.pump();

    expect(tester.getSemantics(status).label, contains('현재 상대 차례'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    sessions.add(
      gameSession(
        status: 'white_timeout_win',
        winnerUserId: 'user-2',
      ),
    );
    await tester.pump();
    await tester.pump();

    final endedLabel = tester.getSemantics(status).label;
    expect(endedLabel, contains('대국이 종료됐습니다'));
    expect(endedLabel, contains('종료 이유: 시간 초과'));
    expect(endedLabel, contains('상대가 이겼습니다'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375pt·200% 큰 글자와 bottom safe area에서 보드와 좌표 시트가 재배치된다',
      (tester) async {
    await pumpAccessibleGame(
      tester,
      size: const Size(375, 844),
      textScale: 2,
      bottomInset: 34,
      disableAnimations: true,
      sessionStream: Stream.value(gameSession()),
      movesStream: Stream.value(const <OmokMove>[]),
    );

    final coordinateButton =
        find.byKey(const ValueKey('omok-coordinate-place-button'));
    expect(tester.getSize(coordinateButton).height, greaterThanOrEqualTo(48));
    expect(tester.getBottomRight(coordinateButton).dy, lessThanOrEqualTo(810));
    final resignButton = find.widgetWithText(OutlinedButton, '기권');
    expect(
      tester.getTopLeft(resignButton).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('내 차례')).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(coordinateButton);
    await tester.pumpAndSettle();

    final sheetPadding = tester.widget<AnimatedPadding>(
      find.byKey(const ValueKey('omok-coordinate-animated-padding')),
    );
    expect(sheetPadding.duration, Duration.zero);

    final row = find.byKey(const ValueKey('omok-coordinate-row'));
    final column = find.byKey(const ValueKey('omok-coordinate-column'));
    expect(
      tester.getTopLeft(column).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(row).dy),
    );

    final cancel = find.byKey(const ValueKey('omok-coordinate-cancel'));
    final confirm = find.byKey(const ValueKey('omok-coordinate-confirm'));
    expect(
      tester.getTopLeft(confirm).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(cancel).dy),
    );
    await tester.scrollUntilVisible(
      confirm,
      180,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('omok-coordinate-sheet')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('다크 모드 대국 chrome은 semantic 색을 쓰고 보드·돌 고유색을 보존한다', (tester) async {
    final theme = AppTheme.dark();
    final moves = [
      OmokMove(
        id: 1,
        sessionId: 'accessible-game',
        moveNo: 1,
        userId: 'user-1',
        stone: 'black',
        x: 7,
        y: 7,
        createdAt: DateTime.now(),
      ),
      OmokMove(
        id: 2,
        sessionId: 'accessible-game',
        moveNo: 2,
        userId: 'user-2',
        stone: 'white',
        x: 4,
        y: 4,
        createdAt: DateTime.now(),
      ),
    ];
    await pumpAccessibleGame(
      tester,
      theme: theme,
      sessionStream: Stream.value(gameSession()),
      movesStream: Stream.value(moves),
    );

    final banner = tester.widget<Container>(
      find.byKey(const ValueKey('omok-connection-banner')),
    );
    final bannerDecoration = banner.decoration! as BoxDecoration;
    expect(bannerDecoration.color, theme.colorScheme.tertiaryContainer);
    expect(
      (bannerDecoration.border! as Border).top.color,
      theme.colorScheme.tertiary,
    );
    expect(
      tester.widget<Text>(find.text('내 차례')).style?.color,
      theme.colorScheme.primary,
    );

    final board = tester.widget<Container>(
      find.byKey(const ValueKey('omok-board-surface')),
    );
    expect((board.decoration! as BoxDecoration).color, DearColors.board);
    final blackStone = tester.widget<Container>(
      find.byKey(const ValueKey('omok-stone-7-7')),
    );
    final whiteStone = tester.widget<Container>(
      find.byKey(const ValueKey('omok-stone-4-4')),
    );
    expect((blackStone.decoration! as BoxDecoration).color, Colors.black);
    expect((whiteStone.decoration! as BoxDecoration).color, Colors.white);

    final marker = tester.widget<Container>(
      find.byKey(const ValueKey('omok-last-move-marker')),
    );
    final markerColor =
        ((marker.decoration! as BoxDecoration).border! as Border).top.color;
    expect(markerColor, DearColors.coralText);
    expect(
      _contrastRatio(markerColor, DearColors.board),
      greaterThanOrEqualTo(3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('대국 종료 후 더보기는 재대결과 규칙을 제공한다', (tester) async {
    configurePhone(tester);
    final session = OmokSessionInfo(
      id: 'game-2',
      coupleId: 'couple-1',
      blackUserId: 'user-1',
      whiteUserId: 'user-2',
      currentTurnUserId: null,
      status: 'black_win',
      winnerUserId: 'user-1',
      turnExpiresAt: null,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          omokSessionProvider.overrideWith(
            (ref, sessionId) => Stream.value(session),
          ),
          omokMovesProvider.overrideWith(
            (ref, sessionId) => const Stream<List<OmokMove>>.empty(),
          ),
          rematchNotificationsProvider.overrideWith(
            (ref, userId) => const Stream<List<OmokNotification>>.empty(),
          ),
        ],
        child: const MaterialApp(home: OmokGamePage(sessionId: 'game-2')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('omok-game-overflow')));
    await tester.pumpAndSettle();
    expect(find.text('재대결 신청'), findsOneWidget);
    expect(find.text('오목 규칙'), findsOneWidget);
    expect(find.text('기권하기'), findsNothing);
  });

  testWidgets('수신 초대는 자동 수락하지 않고 명시적 수락 후에만 대국을 시작한다', (tester) async {
    configurePhone(tester);
    var acceptCalls = 0;
    final controller = StreamController<OmokInviteState?>(sync: true);
    addTearDown(controller.close);
    final router = GoRouter(
      initialLocation: '/omok/invite/incoming-1',
      routes: [
        GoRoute(
          path: '/omok/invite/:inviteId',
          builder: (_, state) => OmokInviteAcceptPage(
            inviteId: state.pathParameters['inviteId']!,
          ),
        ),
        GoRoute(
          path: '/omok/:sessionId',
          builder: (_, state) => Scaffold(
            body: Text('accepted-${state.pathParameters['sessionId']}'),
          ),
        ),
        GoRoute(
          path: '/mini-games',
          builder: (_, __) => const Scaffold(body: Text('오목 메인')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchOmokInviteProvider.overrideWithValue(
            (inviteId) => controller.stream,
          ),
          acceptOmokPushInviteProvider.overrideWithValue((inviteId) async {
            acceptCalls += 1;
            return 'session-1';
          }),
          rejectOmokPushInviteProvider.overrideWithValue((inviteId) async {}),
          expireOmokInviteProvider.overrideWithValue((inviteId) async {}),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    controller.add(
      OmokInviteState(
        id: 'incoming-1',
        status: 'open',
        sessionId: null,
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        inviteType: 'push',
        senderUserId: 'user-2',
        recipientUserId: 'user-1',
        createdAt: DateTime.now(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(acceptCalls, 0);
    expect(find.text('오목 한 판, 함께할까요?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('omok-invite-accept-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('omok-invite-reject-button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('omok-invite-accept-button')),
    );
    await tester.pumpAndSettle();
    expect(acceptCalls, 1);
    expect(find.text('accepted-session-1'), findsOneWidget);
  });

  testWidgets('수신 초대 거절은 reject RPC를 실행하고 Realtime 거절 상태를 표시한다',
      (tester) async {
    configurePhone(tester);
    var rejectCalls = 0;
    var acceptCalls = 0;
    final controller = StreamController<OmokInviteState?>(sync: true);
    addTearDown(controller.close);

    OmokInviteState invite(String status) => OmokInviteState(
          id: 'incoming-2',
          status: status,
          sessionId: null,
          expiresAt: DateTime.now().add(const Duration(minutes: 2)),
          inviteType: 'push',
          senderUserId: 'user-2',
          recipientUserId: 'user-1',
          createdAt: DateTime.now(),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchOmokInviteProvider.overrideWithValue(
            (inviteId) => controller.stream,
          ),
          acceptOmokPushInviteProvider.overrideWithValue((inviteId) async {
            acceptCalls += 1;
            return 'unused';
          }),
          rejectOmokPushInviteProvider.overrideWithValue((inviteId) async {
            rejectCalls += 1;
            controller.add(invite('rejected'));
          }),
          expireOmokInviteProvider.overrideWithValue((inviteId) async {}),
        ],
        child: const MaterialApp(
          home: OmokInviteAcceptPage(inviteId: 'incoming-2'),
        ),
      ),
    );
    await tester.pump();
    controller.add(invite('open'));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('omok-invite-reject-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(rejectCalls, 1);
    expect(acceptCalls, 0);
    expect(find.text('초대를 거절했어요'), findsOneWidget);
    expect(find.text('이 초대로는 대국이 시작되지 않아요.'), findsOneWidget);
  });

  testWidgets('초대 대기실이 대기·상대 거절·만료 상태를 명확히 표시한다', (tester) async {
    configurePhone(tester);
    var expirySyncCalls = 0;
    final controller = StreamController<OmokInviteState?>(sync: true);
    addTearDown(controller.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          watchOmokInviteProvider.overrideWithValue(
            (inviteId) => controller.stream,
          ),
          expireOmokInviteProvider.overrideWithValue((inviteId) async {
            expirySyncCalls += 1;
          }),
        ],
        child: const MaterialApp(
          home: OmokInviteWaitPage(inviteId: 'invite-1', mode: 'push'),
        ),
      ),
    );
    await tester.pump();

    controller.add(
      OmokInviteState(
        id: 'invite-1',
        status: 'open',
        sessionId: null,
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        inviteType: 'push',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('상대 응답을 기다리고 있어요'), findsOneWidget);
    expect(find.text('실시간으로 상대 응답 확인 중'), findsOneWidget);
    expect(find.byKey(const ValueKey('omok-invite-countdown')), findsOneWidget);

    controller.add(
      OmokInviteState(
        id: 'invite-1',
        status: 'rejected',
        sessionId: null,
        expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        inviteType: 'push',
      ),
    );
    await tester.pump();
    expect(find.text('상대가 초대를 거절했어요'), findsOneWidget);

    controller.add(
      OmokInviteState(
        id: 'invite-1',
        status: 'open',
        sessionId: null,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        inviteType: 'push',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('초대가 만료됐어요'), findsOneWidget);
    expect(find.text('새 초대 보내기'), findsOneWidget);
    expect(expirySyncCalls, 1);
  });

  test('거절·만료 migration은 기존 game_enabled 알림 gate와 insert trigger를 보존한다', () {
    final notificationSql = File(
      'supabase/migrations/202607120005_notification_dispatch_pipeline.sql',
    ).readAsStringSync();
    final responseSql = File(
      'supabase/migrations/202607120009_omok_invite_response_state.sql',
    ).readAsStringSync();

    expect(notificationSql, contains('coalesce(np.game_enabled, true)'));
    expect(
      notificationSql,
      contains('create trigger omok_invites_enqueue_push\nafter insert'),
    );
    expect(responseSql, contains('reject_omok_push_invite'));
    expect(responseSql, contains("set status = 'rejected'"));
    expect(responseSql, contains('sender_user_id'));
    expect(
      responseSql,
      isNot(contains('create trigger omok_invites_enqueue_push')),
    );
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance > secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
