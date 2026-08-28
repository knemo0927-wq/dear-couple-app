import 'dart:async';
import 'dart:math';

import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_permission_service.dart';
import 'package:couple_chat_app/src/features/notifications/data/push_registration_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _installationIdKey = 'installation_device_id';

final pushTokenRepositoryProvider = Provider<PushTokenRepository>(
  (ref) => SupabasePushTokenRepository(),
);

final fetchPushTokenProvider = Provider<FetchPushToken>((ref) {
  final messaging = FirebaseMessaging.instance;
  final fetcher = AuthorizedPushTokenFetcher(
    fetchAuthorization: () async {
      final settings = await messaging.getNotificationSettings();
      if (isNotificationAuthorizationGranted(settings.authorizationStatus)) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      return settings.authorizationStatus;
    },
    fetchFcmToken: messaging.getToken,
    fetchApnsToken: messaging.getAPNSToken,
    isIos: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
    delay: Future<void>.delayed,
  );
  return () async {
    try {
      return await fetcher();
    } catch (_) {
      return null;
    }
  };
});

final notificationPermissionServiceProvider =
    Provider<NotificationPermissionService>((ref) {
  final messaging = FirebaseMessaging.instance;
  return NotificationPermissionService(
    fetchAuthorization: () async =>
        (await messaging.getNotificationSettings()).authorizationStatus,
    requestSystemPermission: () async => (await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    ))
        .authorizationStatus,
    configureForegroundNotifications: () =>
        messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    ),
  );
});

final requestNotificationPermissionProvider =
    Provider<RequestNotificationPermissionAction>((ref) {
  final service = ref.watch(notificationPermissionServiceProvider);
  return service.requestFromUserAction;
});

final openNotificationSettingsProvider =
    Provider<OpenNotificationSettingsAction>((ref) {
  return Geolocator.openAppSettings;
});

final fetchDeviceIdProvider = Provider<FetchDeviceId>((ref) {
  return () async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installationIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random();
    final generated =
        '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
    await prefs.setString(_installationIdKey, generated);
    return generated;
  };
});

final fetchPlatformProvider = Provider<FetchPlatform>((ref) {
  return () async => defaultTargetPlatform.name;
});

final pushRegistrationServiceProvider =
    Provider<PushRegistrationService>((ref) {
  return PushRegistrationService(
    repository: ref.watch(pushTokenRepositoryProvider),
    fetchPushToken: ref.watch(fetchPushTokenProvider),
    fetchDeviceId: ref.watch(fetchDeviceIdProvider),
    fetchPlatform: ref.watch(fetchPlatformProvider),
  );
});

class PushRegistrationSync extends ConsumerStatefulWidget {
  const PushRegistrationSync({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  ConsumerState<PushRegistrationSync> createState() =>
      _PushRegistrationSyncState();
}

class _PushRegistrationSyncState extends ConsumerState<PushRegistrationSync> {
  late final ProviderSubscription<AsyncValue<Session?>> _sub;
  StreamSubscription<String>? _tokenRefreshSub;

  @override
  void initState() {
    super.initState();

    _sub = ref.listenManual<AsyncValue<Session?>>(
      authSessionProvider,
      (previous, next) {
        next.whenData((session) {
          unawaited(_sync(session));
          _scheduleFollowUpSyncs(session);
        });
      },
    );

    final initial = ref.read(authSessionProvider);
    initial.whenData((session) {
      unawaited(_sync(session));
      _scheduleFollowUpSyncs(session);
    });

    try {
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
        final latest = ref.read(authSessionProvider);
        latest.whenData((session) {
          unawaited(_sync(session));
        });
      });
    } catch (_) {
      // Firebase unavailable in this runtime.
    }
  }

  void _scheduleFollowUpSyncs(Session? session) {
    if (session == null) return;
    for (final delay in const <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 20),
    ]) {
      Future<void>.delayed(delay, () {
        if (!mounted) return;
        final latest = ref.read(authSessionProvider).valueOrNull;
        if (latest?.user.id != session.user.id) return;
        unawaited(_sync(latest));
      });
    }
  }

  Future<void> _sync(Session? session) async {
    try {
      await ref
          .read(pushRegistrationServiceProvider)
          .syncForSession(userId: session?.user.id);
    } catch (_) {
      // Push registration failure should not block app boot.
    }
  }

  @override
  void dispose() {
    _sub.close();
    unawaited(_tokenRefreshSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
