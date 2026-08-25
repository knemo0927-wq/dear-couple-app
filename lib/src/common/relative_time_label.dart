String formatRelativeActivityLabel(DateTime? timestamp, {DateTime? now}) {
  if (timestamp == null) {
    return '기록 없음';
  }

  final current = now ?? DateTime.now();
  final diff = current.difference(timestamp);
  if (diff.isNegative) {
    return '00분전';
  }

  final minutes = diff.inMinutes;
  if (minutes <= 1) {
    return '방금';
  }
  if (minutes < 60) {
    return '${minutes.toString().padLeft(2, '0')}분전';
  }

  final hours = diff.inHours;
  if (hours < 24) {
    return '${hours.toString().padLeft(2, '0')}시간전';
  }

  return '${diff.inDays}일전';
}
