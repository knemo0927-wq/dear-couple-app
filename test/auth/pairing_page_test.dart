import 'dart:async';

import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/auth/presentation/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('페어링 페이지에서 로그아웃하면 /auth로 이동한다', (tester) async {
    var signOutCalled = false;

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const PairingPage()),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'u1',
              nickname: '테스터',
              pairingCode: 'ABCD',
              coupleId: null,
              avatarPath: null,
            ),
          ),
          authSignOutProvider.overrideWithValue(() async {
            signOutCalled = true;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(signOutCalled, isTrue);
    expect(find.text('auth-screen'), findsOneWidget);
  });

  testWidgets('새 코드 생성은 확인 후 한 번만 RPC provider를 호출하고 결과를 반영한다', (tester) async {
    var rotateCalls = 0;
    final rotation = Completer<String>();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const PairingPage()),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'u1',
              nickname: '테스터',
              pairingCode: 'ABCD',
              coupleId: null,
              avatarPath: null,
            ),
          ),
          rotatePairingCodeProvider.overrideWithValue(() {
            rotateCalls += 1;
            return rotation.future;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    final rotateButton = find.byKey(const Key('rotate-pairing-code-button'));
    await tester.ensureVisible(rotateButton);
    await tester.tap(rotateButton);
    await tester.pumpAndSettle();

    expect(find.text('새 초대 코드를 만들까요?'), findsOneWidget);
    expect(rotateCalls, 0);

    await tester.tap(find.byKey(const Key('confirm-pairing-code-rotation')));
    await tester.pump();

    expect(rotateCalls, 1);
    expect(find.text('생성 중...'), findsOneWidget);

    await tester.tap(rotateButton);
    await tester.pump();
    expect(rotateCalls, 1);

    rotation.complete('ZXCV');
    await tester.pumpAndSettle();

    expect(find.text('ZXCV'), findsOneWidget);
    expect(find.text('새 초대 코드를 만들었어요.'), findsOneWidget);
  });

  testWidgets('코드 회전 실패를 화면에 표시하고 다시 시도할 수 있게 한다', (tester) async {
    var rotateCalls = 0;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const PairingPage()),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'u1',
              nickname: '테스터',
              pairingCode: 'ABCD',
              coupleId: null,
              avatarPath: null,
            ),
          ),
          rotatePairingCodeProvider.overrideWithValue(() async {
            rotateCalls += 1;
            throw StateError('PAIRING_CODE_ROTATION_FAILED');
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    final rotateButton = find.byKey(const Key('rotate-pairing-code-button'));
    await tester.ensureVisible(rotateButton);
    await tester.tap(rotateButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-pairing-code-rotation')));
    await tester.pumpAndSettle();

    expect(rotateCalls, 1);
    expect(
      find.text('요청 처리 중 문제가 발생했어요. 잠시 후 다시 시도해 주세요.'),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(rotateButton).onPressed, isNotNull);
  });

  testWidgets('공유하기는 복사가 아니라 시스템 공유 provider를 호출한다', (tester) async {
    String? sharedCode;
    Rect? sharedOrigin;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const PairingPage()),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'u1',
              nickname: '테스터',
              pairingCode: 'ABCD',
              coupleId: null,
              avatarPath: null,
            ),
          ),
          sharePairingCodeProvider.overrideWithValue(({
            required String code,
            Rect? sharePositionOrigin,
          }) async {
            sharedCode = code;
            sharedOrigin = sharePositionOrigin;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    final shareButton = find.byKey(const Key('share-pairing-code-button'));
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(sharedCode, 'ABCD');
    expect(sharedOrigin, isNotNull);
    expect(find.text('공유 화면을 열었어요.'), findsOneWidget);
  });

  testWidgets('공백과 기호가 섞인 4자리 붙여넣기를 정규화하고 키보드로 연결한다', (tester) async {
    String? pairedCode;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const PairingPage()),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'u1',
              nickname: '테스터',
              pairingCode: 'ABCD',
              coupleId: null,
              avatarPath: null,
            ),
          ),
          pairWithCodeProvider.overrideWithValue((code) async {
            pairedCode = code;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();
    final codeField = find.byKey(const Key('pairing-code-field'));
    await tester.scrollUntilVisible(
      codeField,
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(codeField, 'ab-cd 12!zz');
    await tester.pump();

    expect(tester.widget<TextField>(codeField).controller!.text, 'ABCD');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(pairedCode, 'ABCD');
  });

  testWidgets('390x844 기준 화면에서 보안 과장 문구 없이 페어링 정보를 표시한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const PairingPage()),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-screen')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => const ProfileInfo(
              userId: 'u1',
              nickname: '테스터',
              pairingCode: 'ABCD',
              coupleId: null,
              avatarPath: null,
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final guidance = find.textContaining('초대 코드는 상대방을 확인한 뒤');
    await tester.scrollUntilVisible(
      guidance,
      320,
      scrollable: find.byType(Scrollable).first,
    );

    expect(guidance, findsOneWidget);
    expect(find.textContaining('암호화'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
