import 'package:couple_chat_app/src/features/anniversary/data/anniversary_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:couple_chat_app/src/features/anniversary/data/anniversary_models.dart';

class AnniversaryTimelineCursor {
  const AnniversaryTimelineCursor({
    required this.eventDate,
    required this.stableId,
  });

  final DateTime eventDate;
  final String stableId;
}

class AnniversaryTimelinePage {
  const AnniversaryTimelinePage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<AnniversaryTimelineEntry> items;
  final AnniversaryTimelineCursor? nextCursor;
  final bool hasMore;
}

class AnniversaryRepository {
  AnniversaryRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Stream<List<AnniversaryItem>> watchAnniversaries(String coupleId) {
    return _client
        .from('anniversaries')
        .stream(primaryKey: ['id'])
        .eq('couple_id', coupleId)
        .order('event_date')
        .map(normalizeAnniversaryRows);
  }

  Future<AnniversaryTimelinePage> fetchTimelinePage({
    required String coupleId,
    AnniversaryTimelineCursor? cursor,
    int pageSize = 15,
    DateTime? today,
  }) async {
    final effectiveToday = today ?? DateTime.now();
    final params = <String, dynamic>{
      'target_couple_id': coupleId,
      'page_size': pageSize.clamp(1, 50),
      'cursor_date': cursor == null ? null : _databaseDate(cursor.eventDate),
      'cursor_id': cursor?.stableId,
      'target_today': _databaseDate(effectiveToday),
    };
    final response = await _client.rpc(
      'get_upcoming_anniversary_timeline',
      params: params,
    );
    final rows = (response as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
    final items = rows
        .map((row) => _timelineEntryFromMap(row, coupleId))
        .toList(growable: false);
    final last = items.isEmpty ? null : items.last;
    return AnniversaryTimelinePage(
      items: List<AnniversaryTimelineEntry>.unmodifiable(items),
      nextCursor: last == null
          ? null
          : AnniversaryTimelineCursor(
              eventDate: last.eventDate,
              stableId: last.stableId,
            ),
      hasMore: rows.isNotEmpty && rows.first['has_more'] == true,
    );
  }

  Future<void> addAnniversary({
    required String coupleId,
    required String title,
    required DateTime eventDate,
    AnniversaryRepeat repeat = AnniversaryRepeat.none,
    bool reminderEnabled = true,
    int reminderDaysBefore = 0,
    int reminderHour = 9,
    String? note,
    String? linkedAlbumId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final normalizedTitle = _validatedTitle(title);
    final payload = <String, dynamic>{
      'couple_id': coupleId,
      'title': normalizedTitle,
      'event_date': _databaseDate(eventDate),
      'created_by': user.id,
      'repeat_rule': repeat.databaseValue,
      'reminder_enabled': reminderEnabled,
      'reminder_days_before': reminderDaysBefore.clamp(0, 365),
      'reminder_hour': reminderHour.clamp(0, 23),
      'note': _nullableText(note),
      'linked_album_id': linkedAlbumId,
    };

    await _client.from('anniversaries').insert(payload);
  }

  Future<void> updateAnniversary({
    required String id,
    required String title,
    required DateTime eventDate,
    required AnniversaryRepeat repeat,
    required bool reminderEnabled,
    required int reminderDaysBefore,
    required int reminderHour,
    String? note,
    String? linkedAlbumId,
  }) async {
    final payload = <String, dynamic>{
      'title': _validatedTitle(title),
      'event_date': _databaseDate(eventDate),
      'repeat_rule': repeat.databaseValue,
      'reminder_enabled': reminderEnabled,
      'reminder_days_before': reminderDaysBefore.clamp(0, 365),
      'reminder_hour': reminderHour.clamp(0, 23),
      'note': _nullableText(note),
      'linked_album_id': linkedAlbumId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await _client.from('anniversaries').update(payload).eq('id', id);
  }

  Future<void> removeAnniversary(String id) async {
    await _client.from('anniversaries').delete().eq('id', id);
  }

  String _validatedTitle(String title) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw const AuthException('TITLE_REQUIRED');
    }
    return normalizedTitle;
  }

  String _databaseDate(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.toIso8601String().split('T').first;
  }

  String? _nullableText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

/// Normalizes realtime snapshots without needing a Supabase client. This keeps
/// duplicate-event behavior directly testable and deterministic.
List<AnniversaryItem> normalizeAnniversaryRows(
  Iterable<Map<String, dynamic>> rows,
) {
  final byId = <String, AnniversaryItem>{};
  for (final row in rows) {
    final item = AnniversaryItem.fromMap(row);
    final previous = byId[item.id];
    final itemVersion = item.updatedAt ?? item.createdAt;
    final previousVersion = previous?.updatedAt ?? previous?.createdAt;
    if (previous == null || !itemVersion.isBefore(previousVersion!)) {
      byId[item.id] = item;
    }
  }

  final normalized = byId.values.toList()
    ..sort((a, b) {
      final dateCompare = a.eventDate.compareTo(b.eventDate);
      if (dateCompare != 0) return dateCompare;
      final createdCompare = a.createdAt.compareTo(b.createdAt);
      if (createdCompare != 0) return createdCompare;
      return a.id.compareTo(b.id);
    });
  return List<AnniversaryItem>.unmodifiable(normalized);
}

AnniversaryTimelineEntry _timelineEntryFromMap(
  Map<String, dynamic> map,
  String coupleId,
) {
  final occurrenceDate = DateTime.parse(map['occurrence_date'] as String);
  final kind = switch (map['kind']) {
    'hundred_day' => AnniversaryTimelineKind.hundredDay,
    'yearly' => AnniversaryTimelineKind.yearly,
    _ => AnniversaryTimelineKind.custom,
  };
  AnniversaryItem? customItem;
  if (kind == AnniversaryTimelineKind.custom) {
    customItem = AnniversaryItem(
      id: map['custom_id'] as String,
      coupleId: coupleId,
      title: map['title'] as String,
      eventDate: DateTime.parse(map['custom_event_date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
      repeat: AnniversaryRepeat.fromDatabase(map['repeat_rule']),
      reminderEnabled: map['reminder_enabled'] as bool? ?? true,
      reminderDaysBefore: (map['reminder_days_before'] as num?)?.toInt() ?? 0,
      reminderHour: (map['reminder_hour'] as num?)?.toInt() ?? 9,
      note: map['note'] as String?,
      linkedAlbumId: map['linked_album_id'] as String?,
    );
  }
  return AnniversaryTimelineEntry(
    stableId: map['stable_id'] as String,
    title: map['title'] as String,
    eventDate: occurrenceDate,
    kind: kind,
    customItem: customItem,
    dayCount: (map['day_count'] as num?)?.toInt(),
    yearCount: (map['year_count'] as num?)?.toInt(),
  );
}
