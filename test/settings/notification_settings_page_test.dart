import 'dart:async';

import 'package:couple_chat_app/src/common/app_theme.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_preferences.dart';
import 'package:couple_chat_app/src/features/notifications/data/push_registration_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/push_registration_service.dart';
import 'package:couple_chat_app/src/features/settings/presentation/notification_settings_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('최초 오류를 live region으로 알리고 busy 재시도 뒤 설정을 표시한다', (tester) async {
    final preferences = StreamController<NotificationPreferences>.broadcast();
    addTearDown(preferences.close);
    final semantics = tester.ensureSemantics();

    await _pumpPage(
      tester,
      authStream: Stream.value(_session('user-1')),
      preferencesFor: (_) => preferences.stream,
    );
    await tester.pumpAndSettle();
    preferences.addError(Exception('offline'));
    await tester.pump();
    await tester.pump();

    final error = find.byKey(const Key('notification-preferences-error'));
    expect(error, findsOneWidget);
    expect(
      tester
          .getSemantics(error)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.tap(
      find.descendant(of: error, matching: find.text('다시 시도')),
    );
    await tester.pump();

    expect(find.text('다시 불러오는 중'), findsOneWidget);
    final retryButton = tester.widget<TextButton>(
      find.descendant(of: error, matching: find.byType(TextButton)),
    );
    expect(retryButton.onPressed, isNull);

    preferences.add(_preferences('user-1'));
    await tester.pump();
    await tester.pump();

    expect(error, findsNothing);
    expect(
        find.byKey(const Key('notification-settings-content')), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh 오류 중 마지막 설정과 저장 전 draft를 유지한다', (tester) async {
    final preferences = StreamController<NotificationPreferences>.broadcast();
    addTearDown(preferences.close);

    await _pumpPage(
      tester,
      authStream: Stream.value(_session('user-1')),
      preferencesFor: (_) => preferences.stream,
    );
    preferences.add(_preferences('user-1', messageEnabled: true));
    await tester.pump();
    await tester.pump();

    await tester.tap(_switchTile('메시지 알림'));
    await tester.pump();
    expect(_switchValue(tester, '메시지 알림'), isFalse);

    preferences.addError(Exception('refresh failed'));
    await tester.pump();

    final error = find.byKey(const Key('notification-preferences-error'));
    expect(error, findsOneWidget);
    expect(
        find.byKey(const Key('notification-settings-content')), findsOneWidget);
    expect(_switchValue(tester, '메시지 알림'), isFalse);

    await tester.tap(
      find.descendant(of: error, matching: find.text('다시 시도')),
    );
    await tester.pump();
    expect(find.text('다시 불러오는 중'), findsOneWidget);
    expect(_switchValue(tester, '메시지 알림'), isFalse);

    preferences.add(_preferences('user-1', messageEnabled: true));
    await tester.pump();
    await tester.pump();

    expect(error, findsNothing);
    expect(_switchValue(tester, '메시지 알림'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('저장 중 입력과 중복 저장을 막고 실패한 draft에서 inline 재시도한다', (tester) async {
    final saves = <Completer<void>>[];

    await _pumpPage(
      tester,
      authStream: Stream.value(_session('user-1')),
      preferencesFor: (userId) => Stream.value(
        _preferences(userId, quietEnabled: true),
      ),
      save: (_) {
        final completer = Completer<void>();
        saves.add(completer);
        return completer.future;
      },
    );
    await tester.pumpAndSettle();

    await tester.tap(_switchTile('메시지 알림'));
    await tester.pump();
    expect(_switchValue(tester, '메시지 알림'), isFalse);

    final saveButton = find.byKey(const Key('notification-save-button'));
    await _scrollIntoView(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pump();

    expect(saves, hasLength(1));
    expect(
      tester.widget<DearGradientButton>(saveButton).onPressed,
      isNull,
    );
    expect(
      tester.widget<SwitchListTile>(_switchTile('메시지 알림')).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const Key('notification-quiet-start-dropdown')),
          )
          .onChanged,
      isNull,
    );

    saves.first.completeError(Exception('save failed'));
    await tester.pump();
    await tester.pumpAndSettle();

    final saveError = find.byKey(const Key('notification-save-error'));
    expect(saveError, findsOneWidget);
    expect(find.text('다시 저장'), findsOneWidget);
    expect(_switchValue(tester, '메시지 알림'), isFalse);

    await _scrollIntoView(tester, saveError);
    await tester.tap(
      find.descendant(of: saveError, matching: find.text('다시 저장')),
    );
    await tester.pump();

    expect(saves, hasLength(2));
    expect(find.text('다시 저장하는 중'), findsOneWidget);
    expect(_switchValue(tester, '메시지 알림'), isFalse);
    expect(
      tester.widget<DearGradientButton>(saveButton).onPressed,
      isNull,
    );

    saves.last.complete();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(saveError, findsNothing);
    expect(find.text('알림 설정을 저장했어요.'), findsOneWidget);
    expect(_switchValue(tester, '메시지 알림'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('userId 변경 시 이전 draft와 지연된 저장 결과를 새 사용자에게 적용하지 않는다',
      (tester) async {
    final sessions = StreamController<Session?>.broadcast();
    final userOnePreferences =
        StreamController<NotificationPreferences>.broadcast();
    final userTwoPreferences =
        StreamController<NotificationPreferences>.broadcast();
    final oldSave = Completer<void>();
    addTearDown(sessions.close);
    addTearDown(userOnePreferences.close);
    addTearDown(userTwoPreferences.close);

    await _pumpPage(
      tester,
      authStream: sessions.stream,
      preferencesFor: (userId) => userId == 'user-1'
          ? userOnePreferences.stream
          : userTwoPreferences.stream,
      save: (_) => oldSave.future,
    );

    sessions.add(_session('user-1'));
    await tester.pump();
    await tester.pump();
    userOnePreferences.add(
      _preferences('user-1', messageEnabled: false),
    );
    await tester.pump();
    await tester.pump();

    final saveButton = find.byKey(const Key('notification-save-button'));
    await _scrollIntoView(tester, saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    expect(find.text('저장 중...'), findsOneWidget);

    sessions.add(_session('user-2'));
    await tester.pump();
    await tester.pump();

    expect(
        find.byKey(const Key('notification-settings-content')), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    userOnePreferences.add(
      _preferences('user-1', messageEnabled: false),
    );
    userTwoPreferences.add(
      _preferences('user-2', messageEnabled: true),
    );
    await tester.pump();
    await tester.pump();

    expect(_switchValue(tester, '메시지 알림'), isTrue);
    expect(
      tester.widget<SwitchListTile>(_switchTile('메시지 알림')).onChanged,
      isNotNull,
    );

    oldSave.completeError(Exception('old user save failed'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('notification-save-error')), findsNothing);
    expect(_switchValue(tester, '메시지 알림'), isTrue);
    expect(find.text('알림 설정을 저장했어요.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('375pt와 200% 글자에서 상태 카드와 시간 선택기를 세로 재배치한다', (tester) async {
    await _pumpPage(
      tester,
      size: const Size(375, 844),
      textScale: 2,
      authStream: Stream.value(_session('user-1')),
      preferencesFor: (userId) => Stream.value(
        _preferences(userId, quietEnabled: true),
      ),
    );
    await tester.pumpAndSettle();

    final systemDetails = find.byKey(const Key('notification-system-details'));
    final connectButton = find.byKey(const Key('notification-connect-button'));
    expect(
      tester.getTopLeft(connectButton).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(systemDetails).dy),
    );

    final anniversaryDetails =
        find.byKey(const Key('notification-anniversary-time-details'));
    final anniversaryDropdown =
        find.byKey(const Key('notification-anniversary-hour-dropdown'));
    await _scrollIntoView(tester, anniversaryDropdown);
    expect(
      tester.getTopLeft(anniversaryDropdown).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(anniversaryDetails).dy),
    );

    final quietStart =
        find.byKey(const Key('notification-quiet-start-dropdown'));
    final quietEnd = find.byKey(const Key('notification-quiet-end-dropdown'));
    await _scrollIntoView(tester, quietEnd);
    expect(
      tester.getTopLeft(quietEnd).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(quietStart).dy),
    );
    expect(tester.getTopLeft(quietStart).dx, greaterThanOrEqualTo(0));
    expect(tester.getBottomRight(quietEnd).dx, lessThanOrEqualTo(375));
    expect(tester.takeException(), isNull);
  });

  testWidgets('375pt 정상 배율에서는 기존 가로 배치를 유지한다', (tester) async {
    await _pumpPage(
      tester,
      size: const Size(375, 844),
      authStream: Stream.value(_session('user-1')),
      preferencesFor: (userId) => Stream.value(
        _preferences(userId, quietEnabled: true),
      ),
    );
    await tester.pumpAndSettle();

    final systemDetails = find.byKey(const Key('notification-system-details'));
    final connectButton = find.byKey(const Key('notification-connect-button'));
    expect(
      tester.getTopLeft(connectButton).dy,
      lessThan(tester.getBottomLeft(systemDetails).dy),
    );

    final quietStart =
        find.byKey(const Key('notification-quiet-start-dropdown'));
    final quietEnd = find.byKey(const Key('notification-quiet-end-dropdown'));
    await _scrollIntoView(tester, quietEnd);
    expect(
      tester.getTopLeft(quietEnd).dy,
      closeTo(tester.getTopLeft(quietStart).dy, 1),
    );
    expect(tester.getTopLeft(quietEnd).dx,
        greaterThan(tester.getTopLeft(quietStart).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('권한 사전 설명 뒤 사용자 탭에서만 시스템 권한과 토큰 등록을 실행한다', (tester) async {
    var permissionRequests = 0;
    var systemStatus = const NotificationSystemStatus(
      authorizationStatus: AuthorizationStatus.notDetermined,
      hasFcmToken: false,
      hasApnsToken: false,
    );
    final repository = _FakePushTokenRepository();

    await _pumpPage(
      tester,
      authStream: Stream.value(_session('user-1')),
      preferencesFor: (userId) => Stream.value(_preferences(userId)),
      fetchSystemStatus: () async => systemStatus,
      requestPermission: () async {
        permissionRequests += 1;
        systemStatus = const NotificationSystemStatus(
          authorizationStatus: AuthorizationStatus.authorized,
          hasFcmToken: true,
          hasApnsToken: true,
        );
        return AuthorizationStatus.authorized;
      },
      pushRepository: repository,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('둘만의 메시지와 기념일을 놓치지 않도록 알림을 켤까요?'),
      findsOneWidget,
    );
    expect(find.text('FCM'), findsNothing);
    expect(find.text('APNs'), findsNothing);
    expect(permissionRequests, 0);
    expect(repository.upserts, isEmpty);

    await tester.tap(find.text('알림 켜기'));
    await tester.pumpAndSettle();

    expect(permissionRequests, 1);
    expect(repository.upserts, hasLength(1));
    expect(repository.upserts.single.userId, 'user-1');
    expect(find.text('이 기기 알림이 연결됐어요'), findsOneWidget);
  });

  testWidgets('거절된 권한은 재요청하지 않고 설정 열기로 복구한다', (tester) async {
    var permissionRequests = 0;
    var settingsOpenCount = 0;

    await _pumpPage(
      tester,
      authStream: Stream.value(_session('user-1')),
      preferencesFor: (userId) => Stream.value(_preferences(userId)),
      requestPermission: () async {
        permissionRequests += 1;
        return AuthorizationStatus.denied;
      },
      openSettings: () async {
        settingsOpenCount += 1;
        return true;
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('기기 설정에서 알림을 허용해 주세요'), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();

    expect(settingsOpenCount, 1);
    expect(permissionRequests, 0);
    expect(find.textContaining('기기 설정에서 Dear 알림을 허용'), findsOneWidget);
  });
}

Session _session(String userId) {
  return Session(
    accessToken: 'test-token',
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: const <String, dynamic>{},
      userMetadata: const <String, dynamic>{},
      aud: 'authenticated',
      createdAt: '2026-07-12T00:00:00Z',
    ),
  );
}

NotificationPreferences _preferences(
  String userId, {
  bool messageEnabled = true,
  bool quietEnabled = false,
}) {
  return NotificationPreferences(
    userId: userId,
    messageEnabled: messageEnabled,
    quietEnabled: quietEnabled,
    isServerSynced: true,
  );
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required Stream<Session?> authStream,
  required Stream<NotificationPreferences> Function(String userId)
      preferencesFor,
  Future<void> Function(NotificationPreferences preferences)? save,
  Future<NotificationSystemStatus> Function()? fetchSystemStatus,
  Future<AuthorizationStatus> Function()? requestPermission,
  Future<bool> Function()? openSettings,
  PushTokenRepository? pushRepository,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith((ref) => authStream),
        notificationPreferencesProvider.overrideWith(
          (ref, userId) => preferencesFor(userId),
        ),
        saveNotificationPreferencesProvider.overrideWithValue(
          save ?? (_) async {},
        ),
        notificationSystemStatusProvider.overrideWith(
          (ref) =>
              fetchSystemStatus?.call() ??
              Future.value(
                const NotificationSystemStatus(
                  authorizationStatus: AuthorizationStatus.denied,
                  hasFcmToken: false,
                  hasApnsToken: false,
                ),
              ),
        ),
        requestNotificationPermissionProvider.overrideWithValue(
          requestPermission ?? (() async => AuthorizationStatus.denied),
        ),
        openNotificationSettingsProvider.overrideWithValue(
          openSettings ?? (() async => true),
        ),
        pushRegistrationServiceProvider.overrideWithValue(
          PushRegistrationService(
            repository: pushRepository ?? _FakePushTokenRepository(),
            fetchPushToken: () async => 'test-push-token',
            fetchDeviceId: () async => 'test-device',
            fetchPlatform: () async => 'ios',
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const NotificationSettingsPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder _switchTile(String title) => find.widgetWithText(SwitchListTile, title);

bool _switchValue(WidgetTester tester, String title) =>
    tester.widget<SwitchListTile>(_switchTile(title)).value;

Future<void> _scrollIntoView(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

class _FakePushTokenRepository implements PushTokenRepository {
  final List<PushRegistrationRequest> upserts = [];

  @override
  Future<void> clearByUserAndDevice(String userId, String deviceId) async {}

  @override
  Future<void> upsert(PushRegistrationRequest request) async {
    upserts.add(request);
  }
}
