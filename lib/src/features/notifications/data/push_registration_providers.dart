import 'dart:async';
import 'dart:math';

import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/push_registration_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _installationIdKey = 'installation_device_id';

final pushTokenRepositoryProvider = Provider<PushTokenRepository>(
  (ref) => SupabasePushTokenRepository(),
);

final fetchPushTokenProvider = Provider<FetchPushToken>((ref) {
  return () async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS는 최초 설치 후 알림 허용을 누른 직후 APNs 토큰 준비가 꽤 늦을 수 있다.
        // APNs 토큰 없이 FCM getToken()을 호출하면 null이 될 수 있으므로 최대 60초까지 기다린다.
        for (var i = 0; i < 60; i++) {
          final apns = await messaging.getAPNSToken();
          if (apns != null && apns.isNotEmpty) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      for (var i = 0; i < 30; i++) {
        final token = await messaging.getToken();
        if (token != null && token.trim().isNotEmpty) return token;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      return null;
    } catch (_) {
      return null;
    }
  };
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
      Duration(seconds: 15),
      Duration(seconds: 35),
      Duration(seconds: 70),
      Duration(seconds: 120),
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
