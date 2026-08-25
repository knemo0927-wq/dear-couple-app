import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_repository.dart';
import 'package:couple_chat_app/src/features/auth/presentation/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  GoRouter buildRouter() {
    return GoRouter(
      initialLocation:
          '/auth?from=%2Fchat%2F11111111-1111-4111-8111-111111111111',
      routes: [
        GoRoute(
          path: '/auth',
          builder: (_, __) => const AuthPage(),
        ),
        GoRoute(
          path: '/chat/:coupleId',
          builder: (_, state) => Scaffold(
            body: Text('chat:${state.pathParameters['coupleId']}'),
          ),
        ),
      ],
    );
  }

  testWidgets('로그인 성공 시 from 경로로 복귀한다', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignInProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {}),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'a@test.com');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pumpAndSettle();

    expect(
        find.text('chat:11111111-1111-4111-8111-111111111111'), findsOneWidget);
  });

  testWidgets('로그인 실패 시 친화 에러 메시지를 노출한다', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignInProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {
            throw Exception('Invalid login credentials');
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'a@test.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pumpAndSettle();

    expect(find.text('이메일 또는 비밀번호가 올바르지 않아요.'), findsOneWidget);
  });

  testWidgets('빈 입력으로 로그인 시 검증 메시지를 노출한다', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignInProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {}),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pumpAndSettle();

    expect(find.text('이메일을 입력해 주세요.'), findsOneWidget);
    expect(find.text('비밀번호를 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('이메일 형식과 회원가입 비밀번호 규칙을 입력 즉시 검증한다', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignUpProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {
            return const AuthSignUpResult(emailVerificationPending: true);
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'not-an-email',
    );
    await tester.pump();
    expect(find.text('올바른 이메일 형식을 입력해 주세요.'), findsOneWidget);

    await tester.tap(find.text('회원가입').first);
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      '123',
    );
    await tester.pump();
    expect(find.text('비밀번호는 6자 이상 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('비밀번호 표시 버튼으로 가림 상태를 전환한다', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignInProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {}),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    TextField passwordField = tester.widget(
      find.byKey(const Key('auth-password-field')),
    );
    expect(passwordField.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('password-visibility-toggle')));
    await tester.pump();

    passwordField = tester.widget(
      find.byKey(const Key('auth-password-field')),
    );
    expect(passwordField.obscureText, isFalse);
  });

  testWidgets('비밀번호 키보드 완료 액션으로 로그인한다', (tester) async {
    var signInCalls = 0;
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignInProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {
            signInCalls += 1;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'keyboard@test.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      '123456',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(signInCalls, 1);
    expect(
      find.text('chat:11111111-1111-4111-8111-111111111111'),
      findsOneWidget,
    );
  });

  testWidgets('비밀번호 재설정 provider를 호출하고 완료 상태를 표시한다', (tester) async {
    String? resetEmail;
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authPasswordResetProvider.overrideWithValue((email) async {
            resetEmail = email;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'reset@test.com',
    );
    await tester.tap(find.text('비밀번호를 잊으셨나요?'));
    await tester.pumpAndSettle();

    expect(resetEmail, 'reset@test.com');
    expect(find.text('비밀번호 재설정 메일을 보냈어요.'), findsOneWidget);
  });

  testWidgets('Apple 로그인 버튼이 실제 provider를 호출한다', (tester) async {
    var appleCalls = 0;
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authAppleSignInProvider.overrideWithValue(() async {
            appleCalls += 1;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    final appleButton = find.byKey(const Key('apple-sign-in-button'));
    await tester.ensureVisible(appleButton);
    await tester.tap(appleButton);
    await tester.pumpAndSettle();

    expect(appleCalls, 1);
    expect(find.text('Apple 로그인 화면을 열었어요.'), findsOneWidget);
  });

  testWidgets('인증이 필요한 회원가입 후 대기 상태를 보여주고 해제한다', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignUpProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {
            return const AuthSignUpResult(emailVerificationPending: true);
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('회원가입').first);
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'new@test.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      '123456',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, '회원가입'));
    await tester.pumpAndSettle();

    expect(find.text('이메일을 확인해 주세요'), findsOneWidget);
    expect(find.text('new@test.com'), findsOneWidget);
    expect(find.byKey(const Key('auth-password-field')), findsNothing);

    await tester.tap(find.text('로그인으로 돌아가기'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-password-field')), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsOneWidget);
  });

  testWidgets('390x844 기준 화면에서 인증 UI 레이아웃 오류가 없다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignInProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {}),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('둘만의 공간'), findsOneWidget);
    expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
    expect(find.byKey(const Key('apple-sign-in-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
