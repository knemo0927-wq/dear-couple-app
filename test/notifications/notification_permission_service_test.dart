import 'package:couple_chat_app/src/features/notifications/data/notification_permission_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationPermissionService', () {
    test('사용자 액션에서만 미결정 시스템 권한을 요청한다', () async {
      var requestCount = 0;
      var configureCount = 0;
      final service = NotificationPermissionService(
        fetchAuthorization: () async => AuthorizationStatus.notDetermined,
        requestSystemPermission: () async {
          requestCount += 1;
          return AuthorizationStatus.authorized;
        },
        configureForegroundNotifications: () async {
          configureCount += 1;
        },
      );

      final status = await service.requestFromUserAction();

      expect(status, AuthorizationStatus.authorized);
      expect(requestCount, 1);
      expect(configureCount, 1);
    });

    test('이미 거절된 권한은 프롬프트를 다시 소진하지 않는다', () async {
      var requestCount = 0;
      var configureCount = 0;
      final service = NotificationPermissionService(
        fetchAuthorization: () async => AuthorizationStatus.denied,
        requestSystemPermission: () async {
          requestCount += 1;
          return AuthorizationStatus.authorized;
        },
        configureForegroundNotifications: () async {
          configureCount += 1;
        },
      );

      final status = await service.requestFromUserAction();

      expect(status, AuthorizationStatus.denied);
      expect(requestCount, 0);
      expect(configureCount, 0);
    });
  });

  group('AuthorizedPushTokenFetcher', () {
    test('권한이 없으면 토큰 API와 대기를 호출하지 않는다', () async {
      var fcmCalls = 0;
      var apnsCalls = 0;
      var delays = 0;
      final fetcher = AuthorizedPushTokenFetcher(
        fetchAuthorization: () async => AuthorizationStatus.notDetermined,
        fetchFcmToken: () async {
          fcmCalls += 1;
          return 'unexpected';
        },
        fetchApnsToken: () async {
          apnsCalls += 1;
          return 'unexpected';
        },
        isIos: true,
        delay: (_) async => delays += 1,
      );

      expect(await fetcher(), isNull);
      expect(fcmCalls, 0);
      expect(apnsCalls, 0);
      expect(delays, 0);
    });

    test('iOS APNs와 FCM 준비를 짧고 bounded하게 재시도한다', () async {
      var apnsCalls = 0;
      var fcmCalls = 0;
      var delays = 0;
      final fetcher = AuthorizedPushTokenFetcher(
        fetchAuthorization: () async => AuthorizationStatus.provisional,
        fetchApnsToken: () async {
          apnsCalls += 1;
          if (apnsCalls == 1) return null;
          if (apnsCalls == 2) throw StateError('native token settling');
          return 'apns-token';
        },
        fetchFcmToken: () async {
          fcmCalls += 1;
          return fcmCalls == 1 ? ' ' : 'fcm-token';
        },
        isIos: true,
        maxAttempts: 4,
        retryInterval: const Duration(milliseconds: 10),
        delay: (duration) async {
          expect(duration, const Duration(milliseconds: 10));
          delays += 1;
        },
      );

      expect(await fetcher(), 'fcm-token');
      expect(apnsCalls, 3);
      expect(fcmCalls, 2);
      expect(delays, 3);
    });

    test('APNs가 제한 횟수 안에 준비되지 않으면 FCM을 호출하지 않는다', () async {
      var apnsCalls = 0;
      var fcmCalls = 0;
      final fetcher = AuthorizedPushTokenFetcher(
        fetchAuthorization: () async => AuthorizationStatus.authorized,
        fetchApnsToken: () async {
          apnsCalls += 1;
          return null;
        },
        fetchFcmToken: () async {
          fcmCalls += 1;
          return 'unexpected';
        },
        isIos: true,
        maxAttempts: 3,
        delay: (_) async {},
      );

      expect(await fetcher(), isNull);
      expect(apnsCalls, 3);
      expect(fcmCalls, 0);
    });
  });
}
