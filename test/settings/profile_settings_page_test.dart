import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/settings/presentation/profile_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const profile = ProfileInfo(
    userId: 'user-1',
    nickname: '긴 닉네임도 잘 보이는 우리',
    pairingCode: 'ABCD',
    coupleId: '11111111-1111-4111-8111-111111111111',
    avatarPath: null,
  );

  late GoRouter router;

  setUp(() {
    router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('pairing-destination')),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileSettingsPage(),
        ),
        GoRoute(
          path: '/profile/edit',
          builder: (_, __) => const Scaffold(body: Text('profile-edit-detail')),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const Scaffold(body: Text('notification-detail')),
        ),
        GoRoute(
          path: '/anniversary-reminders',
          builder: (_, __) => const Scaffold(body: Text('anniversary-detail')),
        ),
        GoRoute(
          path: '/travel-map',
          builder: (_, __) => const Scaffold(body: Text('korea-map-detail')),
        ),
        GoRoute(
          path: '/world-map',
          builder: (_, __) => const Scaffold(body: Text('world-map-detail')),
        ),
        GoRoute(
          path: '/mini-games',
          builder: (_, __) => const Scaffold(body: Text('omok-detail')),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
  });

  Future<void> pumpMore(
    WidgetTester tester, {
    List<Override> overrides = const [],
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
          myAvatarUrlProvider.overrideWith((ref) async => null),
          myAccountEmailProvider.overrideWithValue('dear@example.com'),
          ...overrides,
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('더보기 허브가 명세 섹션을 표시하고 가짜 테마 항목은 숨긴다', (tester) async {
    await pumpMore(tester);

    expect(find.text('더보기'), findsOneWidget);
    expect(find.text('우리의 기능'), findsOneWidget);
    expect(find.text('알림과 화면'), findsOneWidget);
    expect(find.text('테마'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-delete-account')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('계정'), findsOneWidget);
    expect(find.text('위험 작업'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);
    expect(find.text('커플 연결 해제'), findsOneWidget);
    expect(find.text('계정 삭제'), findsOneWidget);
  });

  testWidgets('데이터 내보내기는 백엔드 export 후 JSON 공유 액션을 호출한다', (tester) async {
    var exportCalled = false;
    Map<String, dynamic>? sharedData;

    await pumpMore(
      tester,
      overrides: [
        exportMyDataProvider.overrideWithValue(() async {
          exportCalled = true;
          return {'format': 'dear-data-export-v1'};
        }),
        shareDataExportProvider.overrideWithValue(
          (data, {sharePositionOrigin}) async {
            sharedData = data;
          },
        ),
      ],
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-export')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('more-export'))),
      alignment: 0.5,
      duration: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-export')));
    await tester.pumpAndSettle();

    expect(exportCalled, isTrue);
    expect(sharedData, {'format': 'dear-data-export-v1'});
  });

  testWidgets('커플 연결 해제는 영향 확인 뒤 서버 액션을 실행한다', (tester) async {
    var disconnectCalled = false;
    await pumpMore(
      tester,
      overrides: [
        disconnectMyCoupleProvider.overrideWithValue(() async {
          disconnectCalled = true;
        }),
      ],
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-disconnect')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('more-disconnect'))),
      alignment: 0.5,
      duration: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-disconnect')));
    await tester.pumpAndSettle();

    expect(find.text('커플 연결을 해제할까요?'), findsOneWidget);
    expect(disconnectCalled, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, '연결 해제'));
    await tester.pumpAndSettle();

    expect(disconnectCalled, isTrue);
    expect(find.text('pairing-destination'), findsOneWidget);
  });

  testWidgets('프로필 편집은 별도 상세 경로로 이동한다', (tester) async {
    await pumpMore(tester);

    await tester.tap(find.byKey(const ValueKey('more-profile-edit')));
    await tester.pumpAndSettle();

    expect(find.text('profile-edit-detail'), findsOneWidget);
  });

  testWidgets('큰 글자에서도 더보기 핵심 작업이 레이아웃 오류 없이 노출된다', (tester) async {
    await pumpMore(tester, textScale: 2);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('more-delete-account')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('more-delete-account'))),
      alignment: 0.5,
      duration: const Duration(milliseconds: 1),
    );
    await tester.pumpAndSettle();

    expect(find.text('계정 삭제'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
