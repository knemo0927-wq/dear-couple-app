import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat reply 복구 migration은 nullable bigint와 self FK를 검증한다', () {
    final sql = File(
      'supabase/migrations/202608300004_repair_chat_reply.sql',
    ).readAsStringSync();
    final normalized = sql.toLowerCase();

    expect(normalized, startsWith('begin;'));
    expect(normalized.trimRight(), endsWith('commit;'));
    expect(normalized, contains("to_regclass('public.messages')"));
    expect(
      normalized,
      contains('add column if not exists reply_to_message_id bigint'),
    );
    expect(
      normalized,
      contains('alter column reply_to_message_id drop not null'),
    );
    expect(normalized, contains('references public.messages(id)'));
    expect(normalized, contains('on delete set null'));
    expect(normalized, contains("constraint_row.confdeltype = 'n'"));
    expect(normalized, contains('constraint_row.convalidated'));
    expect(
      normalized,
      contains('messages_reply_to_message_id_idx'),
    );
    expect(normalized, contains('where reply_to_message_id is not null'));
    expect(normalized, contains('has an unexpected definition'));
    expect(normalized, contains("notify pgrst, 'reload schema'"));
  });

  test('chat reply 복구 migration은 메시지 행을 삭제하거나 초기화하지 않는다', () {
    final sql = File(
      'supabase/migrations/202608300004_repair_chat_reply.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, isNot(contains('drop table')));
    expect(sql, isNot(contains('truncate')));
    expect(sql, isNot(contains('delete from public.messages')));
    expect(sql, isNot(contains('update public.messages')));
  });
}
