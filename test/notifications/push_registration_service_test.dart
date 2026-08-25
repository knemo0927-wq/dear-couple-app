import 'package:couple_chat_app/src/features/notifications/data/notification_route.dart';
import 'package:couple_chat_app/src/features/notifications/data/push_registration_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePushTokenRepository implements PushTokenRepository {
  int clearCount = 0;
  final List<PushRegistrationRequest> upserts = [];

  @override
  Future<void> clearByUserAndDevice(String userId, String deviceId) async {
    clearCount++;
  }

  @override
  Future<void> upsert(PushRegistrationRequest request) async {
    upserts.add(request);
  }
}

void main() {
  test('푸시 딥링크는 허용된 앱 내부 상세 경로만 통과시킨다', () {
    expect(
      sanitizeNotificationRoute('/chat/couple-1?message=10'),
      '/chat/couple-1?message=10',
    );
    expect(
      sanitizeNotificationRoute('/anniversary-reminders?item=event-1'),
      '/anniversary-reminders?item=event-1',
    );
    expect(
      sanitizeNotificationRoute('/omok/invite/invite-1'),
      '/omok/invite/invite-1',
    );
    expect(sanitizeNotificationRoute('https://evil.example'), isNull);
    expect(sanitizeNotificationRoute('/profile'), isNull);
  });

  test('로그인 상태에서 토큰이 있으면 upsert를 수행한다', () async {
    final repository = _FakePushTokenRepository();
    final service = PushRegistrationService(
      repository: repository,
      fetchPushToken: () async => 'token-1',
      fetchDeviceId: () async => 'device-1',
      fetchPlatform: () async => 'android',
    );

    await service.syncForSession(userId: 'user-1');

    expect(repository.upserts.length, 1);
    expect(repository.upserts.first.userId, 'user-1');
    expect(repository.upserts.first.token, 'token-1');
    expect(repository.clearCount, 0);
  });

  test('로그아웃 상태면 기존 user token을 clear한다', () async {
    final repository = _FakePushTokenRepository();
    final service = PushRegistrationService(
      repository: repository,
      fetchPushToken: () async => 'token-1',
      fetchDeviceId: () async => 'device-1',
      fetchPlatform: () async => 'android',
    );

    await service.syncForSession(userId: 'user-1');
    await service.syncForSession(userId: null);

    expect(repository.clearCount, 1);
  });

  test('같은 user/token이면 중복 upsert를 생략한다', () async {
    final repository = _FakePushTokenRepository();
    final service = PushRegistrationService(
      repository: repository,
      fetchPushToken: () async => 'token-1',
      fetchDeviceId: () async => 'device-1',
      fetchPlatform: () async => 'android',
    );

    await service.syncForSession(userId: 'user-1');
    await service.syncForSession(userId: 'user-1');

    expect(repository.upserts.length, 1);
  });

  test('토큰이 바뀌면 다시 upsert한다', () async {
    final repository = _FakePushTokenRepository();
    var token = 'token-1';
    final service = PushRegistrationService(
      repository: repository,
      fetchPushToken: () async => token,
      fetchDeviceId: () async => 'device-1',
      fetchPlatform: () async => 'android',
    );

    await service.syncForSession(userId: 'user-1');
    token = 'token-2';
    await service.syncForSession(userId: 'user-1');

    expect(repository.upserts.length, 2);
    expect(repository.upserts.last.token, 'token-2');
  });

  test('토큰이 없으면 upsert하지 않는다', () async {
    final repository = _FakePushTokenRepository();
    final service = PushRegistrationService(
      repository: repository,
      fetchPushToken: () async => null,
      fetchDeviceId: () async => 'device-1',
      fetchPlatform: () async => 'android',
    );

    await service.syncForSession(userId: 'user-1');

    expect(repository.upserts, isEmpty);
    expect(repository.clearCount, 0);
  });
}
