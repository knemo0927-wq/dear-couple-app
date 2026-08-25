import 'package:couple_chat_app/src/common/dear_main_tab_nav.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  const profile = ProfileInfo(
    userId: 'user-1',
    nickname: '우리',
    pairingCode: 'ABCD',
    coupleId: '11111111-1111-4111-8111-111111111111',
    avatarPath: null,
  );

  late GoRouter router;

  setUp(() {
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, __, navigationShell) => DearMainTabShell(
            navigationShell: navigationShell,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (_, __) => const _CounterPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/album',
                  builder: (_, __) => const Scaffold(
                    body: Center(child: Text('album-root')),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/more',
                  builder: (_, __) => const Scaffold(
                    body: Center(child: Text('more-root')),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/chat/:coupleId',
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text('chat-detail:${state.pathParameters['coupleId']}'),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('홈·앨범·더보기 브랜치는 탭 전환 뒤에도 상태를 보존한다', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('increment-home')));
    await tester.pump();
    expect(find.text('home-count:1'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pumpAndSettle();
    expect(find.text('album-root'), findsOneWidget);
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      2,
    );

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pumpAndSettle();
    expect(find.text('home-count:1'), findsOneWidget);
  });

  testWidgets('채팅 탭은 독립 상세를 push하고 하단 탭을 숨긴다', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text('chat-detail:11111111-1111-4111-8111-111111111111'),
      findsOneWidget,
    );
    expect(find.byType(BottomNavigationBar), findsNothing);

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('home-count:$_count'),
            FilledButton(
              key: const ValueKey('increment-home'),
              onPressed: () => setState(() => _count++),
              child: const Text('increment'),
            ),
          ],
        ),
      ),
    );
  }
}
