import 'package:couple_chat_app/src/common/app_theme.dart';
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
    expect(find.byKey(const Key('auth-error-summary')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('auth-email-field')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('빈 입력으로 로그인 시 검증 메시지를 노출한다', (tester) async {
    final semantics = tester.ensureSemantics();
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
    final summary = tester.getSemantics(
      find.byKey(const Key('auth-error-summary')),
    );
    expect(summary.label, contains('입력 오류'));
    expect(summary.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('auth-email-field')))
          .focusNode!
          .hasFocus,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'valid@test.com',
    );
    final loginButton = find.widgetWithText(ElevatedButton, '로그인');
    await tester.ensureVisible(loginButton);
    await tester.pump();
    await tester.tap(loginButton);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('auth-password-field')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('이메일과 회원가입 비밀번호는 입력 중이 아닌 blur에서 검증한다', (tester) async {
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
    expect(find.text('올바른 이메일 형식을 입력해 주세요.'), findsNothing);

    await tester.tap(find.byKey(const Key('auth-password-field')));
    await tester.pump();
    expect(find.text('올바른 이메일 형식을 입력해 주세요.'), findsOneWidget);

    await tester.tap(find.text('회원가입').first);
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      '123',
    );
    await tester.pump();
    expect(find.text('비밀번호는 6자 이상 입력해 주세요.'), findsNothing);

    await tester.tap(find.byKey(const Key('auth-email-field')));
    await tester.pump();
    expect(find.text('비밀번호는 6자 이상 입력해 주세요.'), findsOneWidget);
  });

  testWidgets('인증 입력은 지속 라벨·예시 힌트와 비밀번호 자동 완성 정보를 제공한다', (tester) async {
    final router = buildRouter();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    final email = tester.widget<TextField>(
      find.byKey(const Key('auth-email-field')),
    );
    final password = tester.widget<TextField>(
      find.byKey(const Key('auth-password-field')),
    );

    expect(email.decoration?.labelText, '이메일');
    expect(email.decoration?.hintText, '예: name@example.com');
    expect(
      email.decoration?.floatingLabelBehavior,
      FloatingLabelBehavior.always,
    );
    expect(email.textInputAction, TextInputAction.next);
    expect(email.autofillHints, contains(AutofillHints.email));

    expect(password.decoration?.labelText, '비밀번호');
    expect(password.decoration?.hintText, '비밀번호 입력');
    expect(
      password.decoration?.floatingLabelBehavior,
      FloatingLabelBehavior.always,
    );
    expect(password.textInputAction, TextInputAction.done);
    expect(password.autofillHints, contains(AutofillHints.password));

    await tester.tap(find.text('회원가입').first);
    await tester.pump();
    final signUpPassword = tester.widget<TextField>(
      find.byKey(const Key('auth-password-field')),
    );
    expect(signUpPassword.decoration?.hintText, '예: 6자 이상의 비밀번호');
    expect(
      signUpPassword.autofillHints,
      contains(AutofillHints.newPassword),
    );
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

  testWidgets('375pt·200% 글자에서 오류가 표시돼도 인증 UI가 overflow 없이 스크롤된다',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
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
        child: MaterialApp.router(
          routerConfig: router,
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
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, '로그인'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('apple-sign-in-button')));
    await tester.pump();

    expect(find.text('둘만의 공간'), findsOneWidget);
    expect(find.byKey(const Key('auth-error-summary')), findsOneWidget);
    expect(find.byKey(const Key('auth-email-field')), findsOneWidget);
    expect(find.byKey(const Key('apple-sign-in-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('다크 인증 화면은 semantic text·surface 색과 Reduce Motion을 사용한다',
      (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    final theme = AppTheme.dark();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSignInProvider.overrideWithValue(({
            required String email,
            required String password,
          }) async {}),
        ],
        child: MaterialApp.router(
          theme: theme,
          routerConfig: router,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text('둘만의 공간')).style?.color,
      theme.colorScheme.onSurface,
    );
    expect(
      tester.widget<Text>(find.text('함께 나누고, 함께 쌓아가는 우리 이야기')).style?.color,
      theme.colorScheme.onSurfaceVariant,
    );
    final selectedTab = find
        .ancestor(
          of: find.text('로그인').first,
          matching: find.byType(AnimatedContainer),
        )
        .first;
    expect(
        tester.widget<AnimatedContainer>(selectedTab).duration, Duration.zero);
    final appleButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('apple-sign-in-button')),
    );
    expect(
      appleButton.style?.backgroundColor?.resolve({}),
      theme.colorScheme.surface.withValues(alpha: 0.9),
    );
  });
}
