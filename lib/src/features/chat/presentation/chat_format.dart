bool needsDateHeader(DateTime current, DateTime? previous) {
  if (previous == null) return true;
  final currentLocal = current.toLocal();
  final previousLocal = previous.toLocal();
  return currentLocal.year != previousLocal.year ||
      currentLocal.month != previousLocal.month ||
      currentLocal.day != previousLocal.day;
}

String chatDateLabel(DateTime date, {DateTime? now}) {
  final anchor = now ?? DateTime.now();
  final today = DateTime(anchor.year, anchor.month, anchor.day);
  final targetLocal = date.toLocal();
  final target = DateTime(
    targetLocal.year,
    targetLocal.month,
    targetLocal.day,
  );

  final diff = today.difference(target).inDays;
  if (diff == 0) return '오늘';
  if (diff == 1) return '어제';

  return '${target.year}.${_two(target.month)}.${_two(target.day)}';
}

String chatTimeLabel(DateTime date) {
  final local = date.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

bool isSameMinute(DateTime first, DateTime second) {
  final firstLocal = first.toLocal();
  final secondLocal = second.toLocal();
  return firstLocal.year == secondLocal.year &&
      firstLocal.month == secondLocal.month &&
      firstLocal.day == secondLocal.day &&
      firstLocal.hour == secondLocal.hour &&
      firstLocal.minute == secondLocal.minute;
}

String _two(int value) => value.toString().padLeft(2, '0');
