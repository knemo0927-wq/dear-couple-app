import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('삭제된 사진은 durable storage cleanup queue로 이어진다', () {
    final migration = File(
      'supabase/migrations/202607120012_storage_cleanup_queue.sql',
    ).readAsStringSync();
    final worker = File(
      'supabase/functions/process-storage-cleanup/index.ts',
    ).readAsStringSync();

    expect(migration,
        contains('create table if not exists public.storage_cleanup_jobs'));
    expect(migration, contains('messages_queue_deleted_image'));
    expect(migration, contains('memory_photos_queue_deleted_image'));
    expect(migration, contains('travel_photos_queue_deleted_image'));
    expect(migration, contains('world_photos_queue_deleted_image'));
    expect(migration, contains('for update skip locked'));
    expect(migration, contains('claim_storage_cleanup_jobs'));
    expect(migration, contains('finish_storage_cleanup_job'));
    expect(migration, contains('dear-storage-cleanup'));

    expect(worker, contains(".remove([job.object_path])"));
    expect(worker, contains("'finish_storage_cleanup_job'"));
    expect(worker, contains('SERVICE_ROLE_REQUIRED'));
  });
}
