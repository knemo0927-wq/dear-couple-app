import 'dart:developer' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationPreferences {
  const NotificationPreferences({
    required this.userId,
    this.messageEnabled = true,
    this.imageEnabled = true,
    this.anniversaryEnabled = true,
    this.gameEnabled = true,
    this.quietEnabled = false,
    this.quietStartHour = 22,
    this.quietEndHour = 7,
    this.anniversaryHour = 9,
    this.timezone = 'Asia/Seoul',
    this.isServerSynced = false,
  });

  final String userId;
  final bool messageEnabled;
  final bool imageEnabled;
  final bool anniversaryEnabled;
  final bool gameEnabled;
  final bool quietEnabled;
  final int quietStartHour;
  final int quietEndHour;
  final int anniversaryHour;
  final String timezone;
  final bool isServerSynced;

  factory NotificationPreferences.defaults(String userId) {
    return NotificationPreferences(userId: userId);
  }

  factory NotificationPreferences.fromMap(Map<String, dynamic> map) {
    int hourFrom(dynamic value, int fallback) {
      if (value is int) return value.clamp(0, 23);
      if (value is num) return value.toInt().clamp(0, 23);
      final raw = value?.toString() ?? '';
      final parsed = int.tryParse(raw.split(':').first);
      return (parsed ?? fallback).clamp(0, 23);
    }

    return NotificationPreferences(
      userId: map['user_id'] as String,
      messageEnabled: map['message_enabled'] as bool? ?? true,
      imageEnabled: map['image_enabled'] as bool? ?? true,
      anniversaryEnabled: map['anniversary_enabled'] as bool? ?? true,
      gameEnabled: map['game_enabled'] as bool? ?? true,
      quietEnabled: map['quiet_enabled'] as bool? ?? false,
      quietStartHour: hourFrom(map['quiet_start'], 22),
      quietEndHour: hourFrom(map['quiet_end'], 7),
      anniversaryHour: hourFrom(map['anniversary_hour'], 9),
      timezone: (map['timezone'] as String?)?.trim().isNotEmpty == true
          ? (map['timezone'] as String).trim()
          : 'Asia/Seoul',
      isServerSynced: true,
    );
  }

  NotificationPreferences copyWith({
    bool? messageEnabled,
    bool? imageEnabled,
    bool? anniversaryEnabled,
    bool? gameEnabled,
    bool? quietEnabled,
    int? quietStartHour,
    int? quietEndHour,
    int? anniversaryHour,
    String? timezone,
    bool? isServerSynced,
  }) {
    return NotificationPreferences(
      userId: userId,
      messageEnabled: messageEnabled ?? this.messageEnabled,
      imageEnabled: imageEnabled ?? this.imageEnabled,
      anniversaryEnabled: anniversaryEnabled ?? this.anniversaryEnabled,
      gameEnabled: gameEnabled ?? this.gameEnabled,
      quietEnabled: quietEnabled ?? this.quietEnabled,
      quietStartHour: quietStartHour ?? this.quietStartHour,
      quietEndHour: quietEndHour ?? this.quietEndHour,
      anniversaryHour: anniversaryHour ?? this.anniversaryHour,
      timezone: timezone ?? this.timezone,
      isServerSynced: isServerSynced ?? this.isServerSynced,
    );
  }

  Map<String, dynamic> toMap() {
    String time(int hour) => '${hour.toString().padLeft(2, '0')}:00:00';
    return {
      'user_id': userId,
      'message_enabled': messageEnabled,
      'image_enabled': imageEnabled,
      'anniversary_enabled': anniversaryEnabled,
      'game_enabled': gameEnabled,
      'quiet_enabled': quietEnabled,
      'quiet_start': time(quietStartHour),
      'quiet_end': time(quietEndHour),
      'anniversary_hour': anniversaryHour,
      'timezone': timezone,
    };
  }
}

class NotificationPreferencesRepository {
  NotificationPreferencesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<NotificationPreferences> watch(String userId) {
    return _client
        .from('notification_preferences')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map((rows) {
          if (rows.isEmpty) return NotificationPreferences.defaults(userId);
          return NotificationPreferences.fromMap(rows.first);
        })
        .handleError((Object error, StackTrace stackTrace) {
          developer.log(
            'Failed to watch notification preferences.',
            name: 'dear.notifications.preferences',
            error: error,
            stackTrace: stackTrace,
          );
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  Future<void> save(NotificationPreferences preferences) async {
    try {
      await _client.from('notification_preferences').upsert(
            preferences.toMap(),
            onConflict: 'user_id',
          );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to save notification preferences.',
        name: 'dear.notifications.preferences',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

class NotificationSystemStatus {
  const NotificationSystemStatus({
    required this.authorizationStatus,
    required this.hasFcmToken,
    required this.hasApnsToken,
  });

  final AuthorizationStatus authorizationStatus;
  final bool hasFcmToken;
  final bool hasApnsToken;

  bool get isAuthorized =>
      authorizationStatus == AuthorizationStatus.authorized ||
      authorizationStatus == AuthorizationStatus.provisional;

  bool get isProvisional =>
      authorizationStatus == AuthorizationStatus.provisional;

  String get permissionLabel => switch (authorizationStatus) {
        AuthorizationStatus.authorized => '권한 승인',
        AuthorizationStatus.provisional => '권한 임시 허용',
        AuthorizationStatus.denied => '권한 거절',
        AuthorizationStatus.notDetermined => '권한 미결정',
      };
}

final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>(
  (ref) => NotificationPreferencesRepository(),
);

final notificationPreferencesProvider =
    StreamProvider.family<NotificationPreferences, String>((ref, userId) {
  return ref.watch(notificationPreferencesRepositoryProvider).watch(userId);
});

typedef SaveNotificationPreferences = Future<void> Function(
  NotificationPreferences preferences,
);

final saveNotificationPreferencesProvider =
    Provider<SaveNotificationPreferences>((ref) {
  final repository = ref.watch(notificationPreferencesRepositoryProvider);
  return (preferences) async {
    await repository.save(preferences);
    ref.invalidate(notificationPreferencesProvider(preferences.userId));
  };
});

final notificationSystemStatusProvider =
    FutureProvider<NotificationSystemStatus>((ref) async {
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.getNotificationSettings();
    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) {
      return NotificationSystemStatus(
        authorizationStatus: settings.authorizationStatus,
        hasFcmToken: false,
        hasApnsToken: false,
      );
    }
    final fcmToken = await messaging.getToken();
    String? apnsToken;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      apnsToken = await messaging.getAPNSToken();
    }
    return NotificationSystemStatus(
      authorizationStatus: settings.authorizationStatus,
      hasFcmToken: fcmToken?.trim().isNotEmpty == true,
      hasApnsToken: defaultTargetPlatform != TargetPlatform.iOS ||
          apnsToken?.trim().isNotEmpty == true,
    );
  } catch (_) {
    return const NotificationSystemStatus(
      authorizationStatus: AuthorizationStatus.notDetermined,
      hasFcmToken: false,
      hasApnsToken: false,
    );
  }
});
