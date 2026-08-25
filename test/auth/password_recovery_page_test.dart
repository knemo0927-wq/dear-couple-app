import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/presentation/password_recovery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('새 비밀번호는 규칙과 확인 일치를 즉시 검증한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authPasswordUpdateProvider.overrideWithValue((password) async {}),
        ],
        child: const MaterialApp(home: PasswordRecoveryPage()),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('new-password-field')),
      'short',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirm-password-field')),
      'different',
    );
    await tester.tap(find.text('비밀번호 변경'));
    await tester.pump();

    expect(find.text('8자 이상 입력해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호가 서로 같지 않아요.'), findsOneWidget);
  });

  testWidgets('유효한 비밀번호는 서버 변경 액션으로 전달한다', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authPasswordUpdateProvider.overrideWithValue((password) async {
            submitted = password;
          }),
        ],
        child: const MaterialApp(home: PasswordRecoveryPage()),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('new-password-field')),
      'Dear2026!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('confirm-password-field')),
      'Dear2026!',
    );
    await tester.tap(find.text('비밀번호 변경'));
    await tester.pump();

    expect(submitted, 'Dear2026!');
  });
}
