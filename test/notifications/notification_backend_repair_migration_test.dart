import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('알림 backend 복구 migration이 최종 schema와 보안 계약을 포함한다', () async {
    final sql = await File(
      'supabase/migrations/'
      '202608300003_repair_notification_backend.sql',
    ).readAsString();

    expect(sql,
        contains('create table if not exists public.notification_preferences'));
    expect(
        sql, contains('create table if not exists public.notification_jobs'));
    expect(sql, contains('add column if not exists read_at timestamptz'));
    expect(sql, contains('notification_jobs_status_check'));
    expect(sql, contains("'cancelled'"));
    expect(
        sql, contains('insert into public.notification_preferences (user_id)'));
    expect(sql, contains('auth_user_seed_notification_preferences'));
    expect(sql, contains('notification_preferences_touch_and_validate'));
    expect(sql, contains('notification_jobs_touch_updated_at'));
    expect(sql, contains('mark_notification_jobs_read'));
    expect(sql, contains('where user_id = auth.uid()'));
    expect(sql, contains('notification_preferences_select_own'));
    expect(sql, contains('notification_jobs_select_own'));
    expect(sql, contains('grant select, insert, update'));
    expect(sql, contains('grant select on table public.notification_jobs'));
    expect(sql, contains('replica identity full'));
    expect(sql, contains('alter publication supabase_realtime'));
    expect(sql, contains('has an unexpected column contract'));
    expect(sql, contains("notify pgrst, 'reload schema'"));
    expect(sql.trimLeft(), startsWith('begin;'));
    expect(sql.trimRight(), endsWith('commit;'));
  });

  test('복구 migration은 worker나 선택적 기능 table에 의존하지 않는다', () async {
    final sql = await File(
      'supabase/migrations/'
      '202608300003_repair_notification_backend.sql',
    ).readAsString();

    expect(sql, isNot(contains('world_country_photos')));
    expect(sql, isNot(contains('net.http_post')));
    expect(sql, isNot(contains('cron.schedule')));
    expect(sql, isNot(contains('process-notification-jobs')));
  });
}
