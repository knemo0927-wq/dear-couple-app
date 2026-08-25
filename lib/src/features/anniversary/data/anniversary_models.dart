enum AnniversaryRepeat {
  none,
  yearly;

  static AnniversaryRepeat fromDatabase(dynamic value) {
    if (value == true || value == 'yearly' || value == 'annual') {
      return AnniversaryRepeat.yearly;
    }
    return AnniversaryRepeat.none;
  }

  String get databaseValue => switch (this) {
        AnniversaryRepeat.none => 'none',
        AnniversaryRepeat.yearly => 'yearly',
      };
}

class AnniversaryItem {
  const AnniversaryItem({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.eventDate,
    required this.createdAt,
    this.updatedAt,
    this.repeat = AnniversaryRepeat.none,
    this.reminderEnabled = true,
    this.reminderDaysBefore = 0,
    this.reminderHour = 9,
    this.note,
    this.linkedAlbumId,
  });

  final String id;
  final String coupleId;
  final String title;
  final DateTime eventDate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final AnniversaryRepeat repeat;
  final bool reminderEnabled;
  final int reminderDaysBefore;
  final int reminderHour;
  final String? note;
  final String? linkedAlbumId;

  factory AnniversaryItem.fromMap(Map<String, dynamic> map) {
    int boundedInt(dynamic value, int fallback, int min, int max) {
      final parsed =
          value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
      return (parsed ?? fallback).clamp(min, max);
    }

    final createdAt = DateTime.parse(map['created_at'] as String);
    final repeatValue = map.containsKey('repeat_rule')
        ? map['repeat_rule']
        : map['repeat_annually'];

    return AnniversaryItem(
      id: map['id'] as String,
      coupleId: map['couple_id'] as String,
      title: map['title'] as String,
      eventDate: DateTime.parse(map['event_date'] as String),
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? createdAt,
      repeat: AnniversaryRepeat.fromDatabase(repeatValue),
      reminderEnabled: map['reminder_enabled'] as bool? ?? true,
      reminderDaysBefore: boundedInt(map['reminder_days_before'], 0, 0, 365),
      reminderHour: boundedInt(map['reminder_hour'], 9, 0, 23),
      note: map['note'] as String?,
      linkedAlbumId: map['linked_album_id'] as String?,
    );
  }

  AnniversaryItem copyWith({
    String? title,
    DateTime? eventDate,
    DateTime? updatedAt,
    AnniversaryRepeat? repeat,
    bool? reminderEnabled,
    int? reminderDaysBefore,
    int? reminderHour,
    String? note,
    String? linkedAlbumId,
  }) {
    return AnniversaryItem(
      id: id,
      coupleId: coupleId,
      title: title ?? this.title,
      eventDate: eventDate ?? this.eventDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      repeat: repeat ?? this.repeat,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
      reminderHour: reminderHour ?? this.reminderHour,
      note: note ?? this.note,
      linkedAlbumId: linkedAlbumId ?? this.linkedAlbumId,
    );
  }
}

enum AnniversaryTimelineKind {
  hundredDay,
  yearly,
  custom,
}

class AnniversaryTimelineEntry {
  const AnniversaryTimelineEntry({
    required this.stableId,
    required this.title,
    required this.eventDate,
    required this.kind,
    this.customItem,
    this.dayCount,
    this.yearCount,
  });

  final String stableId;
  final String title;
  final DateTime eventDate;
  final AnniversaryTimelineKind kind;
  final AnniversaryItem? customItem;
  final int? dayCount;
  final int? yearCount;

  bool get isCustom => kind == AnniversaryTimelineKind.custom;

  bool get reminderEnabled => customItem?.reminderEnabled ?? true;
}
