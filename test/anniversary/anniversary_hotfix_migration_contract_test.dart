import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기념일 전체보기 hotfix는 부분 배포 스키마와 RPC 계약을 복구한다', () {
    final migration = File(
      'supabase/migrations/'
      '202607140001_anniversary_timeline_compatibility_hotfix.sql',
    ).readAsStringSync();

    expect(migration.trimLeft(), startsWith('begin;'));
    expect(migration.trimRight(), endsWith('commit;'));

    for (final column in [
      'repeat_rule',
      'reminder_enabled',
      'reminder_days_before',
      'reminder_hour',
      'note',
      'linked_album_id',
      'updated_at',
    ]) {
      expect(migration, contains('add column if not exists $column'));
    }

    expect(
      migration,
      contains('create or replace function public.anniversary_occurrence_date'),
    );
    expect(
      migration,
      contains(
        'create or replace function public.get_upcoming_anniversary_timeline',
      ),
    );
    expect(migration, contains('security definer'));
    expect(migration, contains('public.current_user_has_couple'));
    expect(migration, contains('cursor_date is null'));
    expect(migration, contains('stable_id > coalesce(cursor_id'));
    expect(migration, contains('to authenticated;'));
    expect(migration, contains("notify pgrst, 'reload schema';"));

    expect(migration, isNot(contains('create table')));
    expect(migration, isNot(contains('notification_preferences')));
    expect(migration, isNot(contains('conversation_reads')));
    expect(migration, isNot(contains('pair_with_code')));
  });
}
