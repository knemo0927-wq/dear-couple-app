import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationInboxItem {
  const NotificationInboxItem({
    required this.id,
    required this.category,
    required this.route,
    required this.payload,
    required this.status,
    required this.createdAt,
    required this.readAt,
  });

  final String id;
  final String category;
  final String route;
  final Map<String, dynamic> payload;
  final String status;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isUnread =>
      readAt == null && status != 'cancelled' && status != 'failed';
  String get title => payload['title']?.toString().trim().isNotEmpty == true
      ? payload['title'].toString()
      : 'Dear 알림';
  String get body => payload['body']?.toString().trim().isNotEmpty == true
      ? payload['body'].toString()
      : switch (category) {
          'anniversary' => '소중한 기념일이 찾아왔어요.',
          'image' => '새 사진이 도착했어요.',
          'game' => '오목 초대가 도착했어요.',
          _ => '새 메시지가 도착했어요.',
        };

  factory NotificationInboxItem.fromMap(Map<String, dynamic> map) {
    final rawPayload = map['payload'];
    return NotificationInboxItem(
      id: map['id'] as String,
      category: map['category'] as String,
      route: map['route'] as String,
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'] as String),
    );
  }
}

class NotificationInboxRepository {
  NotificationInboxRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<List<NotificationInboxItem>> watch(String userId) {
    return _client
        .from('notification_jobs')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50)
        .map(
          (rows) => rows
              .map(
                (row) => NotificationInboxItem.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false),
        )
        .handleError((Object error, StackTrace stackTrace) {
          developer.log(
            'Failed to watch the notification inbox.',
            name: 'dear.notifications.inbox',
            error: error,
            stackTrace: stackTrace,
          );
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  Future<void> markRead(Iterable<String> ids) async {
    final uniqueIds = ids.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) return;
    try {
      await _client.rpc(
        'mark_notification_jobs_read',
        params: {'target_job_ids': uniqueIds},
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to mark notification jobs as read.',
        name: 'dear.notifications.inbox',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final notificationInboxRepositoryProvider =
    Provider<NotificationInboxRepository>(
  (ref) => NotificationInboxRepository(),
);

final notificationInboxProvider =
    StreamProvider.family<List<NotificationInboxItem>, String>((ref, userId) {
  return ref.watch(notificationInboxRepositoryProvider).watch(userId);
});

final markNotificationReadProvider =
    Provider<Future<void> Function(Iterable<String>)>((ref) {
  return ref.watch(notificationInboxRepositoryProvider).markRead;
});
