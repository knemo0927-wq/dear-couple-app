import 'package:couple_chat_app/src/app_root.dart';
import 'package:couple_chat_app/src/app_router.dart';
import 'package:couple_chat_app/src/config/app_config.dart';
import 'package:couple_chat_app/src/config/app_config_provider.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/auth/presentation/auth_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const configured = AppConfig(
    supabaseUrl: 'http://localhost:54321',
    supabaseAnonKey: 'test-key',
  );

  testWidgets('비로그인 사용자가 chat 딥링크로 들어오면 auth 페이지로 이동한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(configured),
          hasSessionStateProvider
              .overrideWithValue(const AsyncValue.data(false)),
          routerInitialLocationProvider
              .overrideWithValue('/chat/11111111-1111-4111-8111-111111111111'),
        ],
        child: const CoupleChatApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('로그인 / 회원가입'), findsOneWidget);
  });

  testWidgets('인증 상태 에러면 오프라인 fallback 페이지를 노출한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(configured),
          hasSessionStateProvider.overrideWithValue(
            AsyncValue<bool>.error(
                Exception('auth stream failed'), StackTrace.empty),
          ),
          routerInitialLocationProvider.overrideWithValue('/'),
        ],
        child: const CoupleChatApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('오프라인 상태'), findsOneWidget);
    expect(find.text('네트워크 또는 인증 서버 상태를 확인해 주세요.'), findsOneWidget);
  });

  testWidgets('로그인 상태에서 잘못된 chat 링크면 invalid 링크 페이지를 보여준다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(configured),
          hasSessionStateProvider
              .overrideWithValue(const AsyncValue.data(true)),
          routerInitialLocationProvider.overrideWithValue('/chat/not-a-uuid'),
        ],
        child: const CoupleChatApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('잘못된 채팅 링크'), findsOneWidget);
    expect(find.text('유효하지 않은 채팅 링크예요.'), findsOneWidget);
  });
}
