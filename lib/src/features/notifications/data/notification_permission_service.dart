import 'package:firebase_messaging/firebase_messaging.dart';

typedef FetchNotificationAuthorization = Future<AuthorizationStatus> Function();
typedef RequestSystemNotificationPermission = Future<AuthorizationStatus>
    Function();
typedef RequestNotificationPermissionAction = Future<AuthorizationStatus>
    Function();
typedef OpenNotificationSettingsAction = Future<bool> Function();
typedef ConfigureForegroundNotifications = Future<void> Function();
typedef FetchMessagingToken = Future<String?> Function();
typedef NotificationRetryDelay = Future<void> Function(Duration duration);

bool isNotificationAuthorizationGranted(AuthorizationStatus status) {
  return status == AuthorizationStatus.authorized ||
      status == AuthorizationStatus.provisional;
}

/// Keeps the one-shot operating-system prompt behind an explicit user action.
class NotificationPermissionService {
  const NotificationPermissionService({
    required this.fetchAuthorization,
    required this.requestSystemPermission,
    required this.configureForegroundNotifications,
  });

  final FetchNotificationAuthorization fetchAuthorization;
  final RequestSystemNotificationPermission requestSystemPermission;
  final ConfigureForegroundNotifications configureForegroundNotifications;

  Future<AuthorizationStatus> requestFromUserAction() async {
    var status = await fetchAuthorization();
    if (status == AuthorizationStatus.notDetermined) {
      status = await requestSystemPermission();
    }
    if (isNotificationAuthorizationGranted(status)) {
      await configureForegroundNotifications();
    }
    return status;
  }
}

/// Fetches an existing token without ever displaying a permission prompt.
///
/// Token availability can lag behind authorization on iOS. Polling is bounded
/// to a few seconds so session startup never waits through the old 90-second
/// APNs/FCM sequence.
class AuthorizedPushTokenFetcher {
  const AuthorizedPushTokenFetcher({
    required this.fetchAuthorization,
    required this.fetchFcmToken,
    required this.fetchApnsToken,
    required this.isIos,
    required this.delay,
    this.maxAttempts = 8,
    this.retryInterval = const Duration(milliseconds: 500),
  });

  final FetchNotificationAuthorization fetchAuthorization;
  final FetchMessagingToken fetchFcmToken;
  final FetchMessagingToken fetchApnsToken;
  final bool isIos;
  final NotificationRetryDelay delay;
  final int maxAttempts;
  final Duration retryInterval;

  Future<String?> call() async {
    final authorization = await fetchAuthorization();
    if (!isNotificationAuthorizationGranted(authorization)) return null;

    if (isIos) {
      final apnsToken = await _poll(fetchApnsToken);
      if (apnsToken == null) return null;
    }
    return _poll(fetchFcmToken);
  }

  Future<String?> _poll(FetchMessagingToken fetch) async {
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      try {
        final token = (await fetch())?.trim();
        if (token != null && token.isNotEmpty) return token;
      } catch (_) {
        // Firebase may briefly reject token reads while native registration is
        // settling. A later bounded attempt can still succeed.
      }
      if (attempt + 1 < attempts) await delay(retryInterval);
    }
    return null;
  }
}
