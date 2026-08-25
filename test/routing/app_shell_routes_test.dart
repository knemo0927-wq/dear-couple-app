import 'package:couple_chat_app/src/app_router.dart';
import 'package:couple_chat_app/src/config/app_config.dart';
import 'package:couple_chat_app/src/config/app_config_provider.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/settings/data/couple_prefs_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const configured = AppConfig(
    supabaseUrl: 'http://localhost:54321',
    supabaseAnonKey: 'test-key',
  );
  const profile = ProfileInfo(
    userId: 'user-1',
    nickname: '우리',
    pairingCode: 'ABCD',
    coupleId: '11111111-1111-4111-8111-111111111111',
    avatarPath: null,
  );

  Widget buildApp(String initialLocation) {
    return ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(configured),
        hasSessionStateProvider.overrideWithValue(const AsyncValue.data(true)),
        routerInitialLocationProvider.overrideWithValue(initialLocation),
        myProfileProvider.overrideWith((ref) async => profile),
        myAvatarUrlProvider.overrideWith((ref) async => null),
        myAccountEmailProvider.overrideWithValue('dear@example.com'),
        anniversaryDateProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: const _RouterHarness(),
    );
  }

  testWidgets('/profile 루트에는 공통 하단 탭을 표시한다', (tester) async {
    await tester.pumpWidget(buildApp('/profile'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('더보기'),
      ),
      findsOneWidget,
    );
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets('/profile/edit 상세에는 하단 탭을 표시하지 않는다', (tester) async {
    await tester.pumpWidget(buildApp('/profile/edit'));
    await tester.pumpAndSettle();

    expect(find.text('프로필 편집'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });
}

class _RouterHarness extends ConsumerWidget {
  const _RouterHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(routerConfig: ref.watch(goRouterProvider));
  }
}
