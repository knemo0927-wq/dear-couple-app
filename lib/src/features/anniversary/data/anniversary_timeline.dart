import 'package:couple_chat_app/src/features/anniversary/data/anniversary_models.dart';

/// Builds the single future-facing anniversary timeline used by Home, the
/// dashboard and the full list. Automatic and custom entries intentionally
/// keep distinct stable IDs, so two celebrations on the same date both remain.
List<AnniversaryTimelineEntry> buildUpcomingAnniversaryTimeline({
  required DateTime? relationshipStart,
  required Iterable<AnniversaryItem> customItems,
  required int limit,
  DateTime? now,
}) {
  if (limit <= 0) return const <AnniversaryTimelineEntry>[];

  final today = anniversaryDateOnly(now ?? DateTime.now());
  final entries = <AnniversaryTimelineEntry>[];

  if (relationshipStart != null) {
    final start = anniversaryDateOnly(relationshipStart);
    final currentDay = today.difference(start).inDays + 1;
    var dayCount = (((currentDay < 1 ? 1 : currentDay) + 99) ~/ 100) * 100;
    if (dayCount < 100) dayCount = 100;

    for (var index = 0; index < limit; index += 1) {
      final eventDate = start.add(Duration(days: dayCount - 1));
      entries.add(
        AnniversaryTimelineEntry(
          stableId: 'automatic:hundred:$dayCount',
          title: '$dayCount일',
          eventDate: eventDate,
          kind: AnniversaryTimelineKind.hundredDay,
          dayCount: dayCount,
        ),
      );
      dayCount += 100;
    }

    var yearCount = today.year - start.year;
    if (yearCount < 1) yearCount = 1;
    var addedYears = 0;
    while (addedYears < limit) {
      final eventDate = anniversaryDateForYear(start, yearCount);
      if (!eventDate.isBefore(today)) {
        entries.add(
          AnniversaryTimelineEntry(
            stableId: 'automatic:year:$yearCount',
            title: '$yearCount주년',
            eventDate: eventDate,
            kind: AnniversaryTimelineKind.yearly,
            yearCount: yearCount,
          ),
        );
        addedYears += 1;
      }
      yearCount += 1;
    }
  }

  final customById = <String, AnniversaryItem>{};
  for (final item in customItems) {
    final previous = customById[item.id];
    final itemVersion = item.updatedAt ?? item.createdAt;
    final previousVersion = previous?.updatedAt ?? previous?.createdAt;
    if (previous == null || itemVersion.isAfter(previousVersion!)) {
      customById[item.id] = item;
    }
  }

  for (final item in customById.values) {
    final eventDate = nextCustomAnniversaryOccurrence(item, today: today);
    if (eventDate == null) continue;
    entries.add(
      AnniversaryTimelineEntry(
        stableId: 'custom:${item.id}',
        title: item.title,
        eventDate: eventDate,
        kind: AnniversaryTimelineKind.custom,
        customItem: item,
      ),
    );
  }

  entries.sort(compareAnniversaryTimelineEntries);
  return List<AnniversaryTimelineEntry>.unmodifiable(entries.take(limit));
}

int compareAnniversaryTimelineEntries(
  AnniversaryTimelineEntry a,
  AnniversaryTimelineEntry b,
) {
  final dateCompare = a.eventDate.compareTo(b.eventDate);
  if (dateCompare != 0) return dateCompare;

  final kindCompare = _kindPriority(a.kind).compareTo(_kindPriority(b.kind));
  if (kindCompare != 0) return kindCompare;

  if (a.kind == AnniversaryTimelineKind.custom &&
      b.kind == AnniversaryTimelineKind.custom) {
    final aCreatedAt = a.customItem?.createdAt;
    final bCreatedAt = b.customItem?.createdAt;
    if (aCreatedAt != null && bCreatedAt != null) {
      final createdCompare = aCreatedAt.compareTo(bCreatedAt);
      if (createdCompare != 0) return createdCompare;
    }
  }

  return a.stableId.compareTo(b.stableId);
}

DateTime? nextCustomAnniversaryOccurrence(
  AnniversaryItem item, {
  required DateTime today,
}) {
  final normalizedToday = anniversaryDateOnly(today);
  final originalDate = anniversaryDateOnly(item.eventDate);
  if (item.repeat == AnniversaryRepeat.none) {
    return originalDate.isBefore(normalizedToday) ? null : originalDate;
  }

  var targetYear = normalizedToday.year;
  if (targetYear < originalDate.year) targetYear = originalDate.year;
  var occurrence =
      anniversaryDateForYear(originalDate, targetYear - originalDate.year);
  if (occurrence.isBefore(normalizedToday)) {
    occurrence = anniversaryDateForYear(
      originalDate,
      targetYear - originalDate.year + 1,
    );
  }
  return occurrence;
}

DateTime anniversaryDateForYear(DateTime start, int yearCount) {
  final normalized = anniversaryDateOnly(start);
  final targetYear = normalized.year + yearCount;
  final targetDay = normalized.day.clamp(
    1,
    _daysInMonth(targetYear, normalized.month),
  );
  return DateTime(targetYear, normalized.month, targetDay);
}

DateTime anniversaryDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

int _kindPriority(AnniversaryTimelineKind kind) => switch (kind) {
      AnniversaryTimelineKind.hundredDay => 0,
      AnniversaryTimelineKind.yearly => 1,
      AnniversaryTimelineKind.custom => 2,
    };

int _daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}
