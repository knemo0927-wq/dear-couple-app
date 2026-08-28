import 'package:couple_chat_app/src/app_router.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('잘못된 채팅 링크 페이지가 안내 문구를 보여준다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: InvalidChatLinkPage(),
      ),
    );

    expect(find.text('잘못된 채팅 링크'), findsOneWidget);
    expect(find.text('유효하지 않은 채팅 링크예요.'), findsOneWidget);
    expect(find.text('홈으로 이동'), findsOneWidget);
  });

  testWidgets('상세 화면은 플랫폼 기본 route와 Reduce Motion 무전환을 사용한다', (tester) async {
    Page<void>? capturedPage;

    Future<void> pumpPage({
      required TargetPlatform platform,
      bool disableAnimations = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          themeAnimationDuration: Duration.zero,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Builder(
              builder: (context) {
                capturedPage = buildDearAdaptivePage(
                  context: context,
                  key: const ValueKey('adaptive-route'),
                  child: const Text('detail'),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpPage(platform: TargetPlatform.iOS);
    expect(capturedPage, isA<CupertinoPage<void>>());

    await pumpPage(platform: TargetPlatform.android);
    expect(capturedPage, isA<MaterialPage<void>>());

    await pumpPage(
      platform: TargetPlatform.iOS,
      disableAnimations: true,
    );
    expect(capturedPage, isA<NoTransitionPage<void>>());
  });
}
