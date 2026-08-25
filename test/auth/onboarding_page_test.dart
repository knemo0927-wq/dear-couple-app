import 'package:couple_chat_app/src/features/onboarding/presentation/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const OnboardingPage(),
        ),
        GoRoute(
          path: '/auth',
          builder: (_, __) => const Scaffold(body: Text('auth-screen')),
        ),
      ],
    );
  }

  testWidgets('채팅, 앨범, 기념일, 여행 지도, 알림을 순서대로 소개한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: buildRouter()),
    );
    await tester.pumpAndSettle();

    expect(find.text('둘만의 대화'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('함께 쌓는 추억 앨범'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('다가오는 기념일'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('함께 채우는 여행 지도'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('중요한 순간을 놓치지 않게'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboarding-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('auth-screen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390x844 화면의 큰 글자에서도 레이아웃 오류가 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: buildRouter(),
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('둘만의 대화'), findsOneWidget);
    expect(find.text('다음'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
