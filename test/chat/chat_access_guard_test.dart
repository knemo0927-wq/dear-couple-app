import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_access_guard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('프로필 조회 에러 시 안내 문구를 노출한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith(
            (ref) async => throw Exception('profile load failed'),
          ),
        ],
        child: const MaterialApp(
          home: ChatAccessGuardPage(
              coupleId: '11111111-1111-4111-8111-111111111111'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('프로필을 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('페어링 화면으로 이동'), findsOneWidget);
  });
}
