import 'package:couple_chat_app/src/routing/route_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveTopLevelRedirect', () {
    test('설정이 없으면 setup 이외 경로는 /setup으로 보낸다', () {
      final redirect = resolveTopLevelRedirect(
        hasSupabaseConfig: false,
        hasSession: false,
        hasAuthError: false,
        location: '/chat/abc',
      );

      expect(redirect, '/setup');
    });

    test('인증 에러가 있으면 /offline으로 보낸다', () {
      final redirect = resolveTopLevelRedirect(
        hasSupabaseConfig: true,
        hasSession: false,
        hasAuthError: true,
        location: '/chat/11111111-1111-1111-1111-111111111111',
      );

      expect(redirect, '/offline');
    });

    test('설정이 있고 세션이 없으면 auth 이외 경로는 from 쿼리와 함께 /auth로 보낸다', () {
      final redirect = resolveTopLevelRedirect(
        hasSupabaseConfig: true,
        hasSession: false,
        hasAuthError: false,
        location: '/chat/11111111-1111-1111-1111-111111111111',
      );

      expect(redirect,
          '/auth?from=%2Fchat%2F11111111-1111-1111-1111-111111111111');
    });

    test('세션이 없고 /auth 접근은 통과시킨다', () {
      final redirect = resolveTopLevelRedirect(
        hasSupabaseConfig: true,
        hasSession: false,
        hasAuthError: false,
        location: '/auth',
      );

      expect(redirect, isNull);
    });

    test('세션이 있으면 /auth 접근 시 루트로 보낸다', () {
      final redirect = resolveTopLevelRedirect(
        hasSupabaseConfig: true,
        hasSession: true,
        hasAuthError: false,
        location: '/auth',
      );

      expect(redirect, '/');
    });

    test('세션이 있으면 /offline 접근 시 루트로 보낸다', () {
      final redirect = resolveTopLevelRedirect(
        hasSupabaseConfig: true,
        hasSession: true,
        hasAuthError: false,
        location: '/offline',
      );

      expect(redirect, '/');
    });

    test('세션이 있으면 /chat 딥링크는 통과시킨다', () {
      final redirect = resolveTopLevelRedirect(
        hasSupabaseConfig: true,
        hasSession: true,
        hasAuthError: false,
        location: '/chat/11111111-1111-1111-1111-111111111111',
      );

      expect(redirect, isNull);
    });
  });

  group('resolvePostLoginDestination', () {
    test('from이 없으면 루트로 이동한다', () {
      expect(resolvePostLoginDestination(null), '/');
    });

    test('from이 상대 경로가 아니면 루트로 이동한다', () {
      expect(resolvePostLoginDestination('https://evil.example'), '/');
    });

    test('유효한 from이면 해당 경로로 이동한다', () {
      expect(
          resolvePostLoginDestination(
              '/chat/11111111-1111-4111-8111-111111111111'),
          '/chat/11111111-1111-4111-8111-111111111111');
    });
  });

  group('isValidCoupleId', () {
    test('UUID 형식은 유효하다', () {
      expect(isValidCoupleId('11111111-1111-4111-8111-111111111111'), isTrue);
    });

    test('빈 문자열은 유효하지 않다', () {
      expect(isValidCoupleId(''), isFalse);
    });

    test('UUID 형식이 아니면 유효하지 않다', () {
      expect(isValidCoupleId('couple-123'), isFalse);
    });
  });
}
