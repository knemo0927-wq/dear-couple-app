import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final anniversaryDateProvider = StreamProvider<DateTime?>((ref) {
  final profile = ref.watch(myProfileProvider).valueOrNull;
  if (profile == null || !profile.isPaired) {
    return Stream.value(null);
  }

  return Supabase.instance.client
      .from('couples')
      .stream(primaryKey: ['id'])
      .eq('id', profile.coupleId!)
      .limit(1)
      .map((rows) {
        if (rows.isEmpty) return null;
        final raw = rows.first['anniversary_date'] as String?;
        if (raw == null || raw.trim().isEmpty) return null;
        return DateTime.tryParse(raw);
      });
});

typedef SetAnniversaryDateAction = Future<void> Function({
  required String coupleId,
  required DateTime? date,
});

final setAnniversaryDateProvider = Provider<SetAnniversaryDateAction>((ref) {
  return ({required coupleId, required date}) async {
    final normalized = date == null
        ? null
        : DateUtils.dateOnly(date).toIso8601String().split('T').first;
    await Supabase.instance.client
        .from('couples')
        .update({'anniversary_date': normalized}).eq('id', coupleId);

    ref.invalidate(anniversaryDateProvider);
  };
});

String anniversaryDdayLabel(DateTime date, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final anniversary = DateUtils.dateOnly(date);
  final diff = today.difference(anniversary).inDays;

  if (diff >= 0) {
    return 'D+${diff + 1}';
  }
  return 'D$diff';
}

String anniversaryDateKoreanLabel(DateTime date) {
  final normalized = DateUtils.dateOnly(date);
  return '${normalized.year}.${normalized.month.toString().padLeft(2, '0')}.${normalized.day.toString().padLeft(2, '0')}';
}
