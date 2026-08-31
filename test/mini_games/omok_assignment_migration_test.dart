import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/'
      '202608310001_omok_result_based_stone_assignment.sql',
    ).readAsStringSync().toLowerCase();
  });

  test('오목 돌 배정 migration은 신규 세션의 배정 근거를 기록한다', () {
    expect(sql.trimLeft(), startsWith('begin;'));
    expect(sql.trimRight(), endsWith('commit;'));
    expect(sql, contains('add column if not exists stone_assignment_reason'));
    expect(
      sql,
      contains(
        'add column if not exists stone_assignment_source_session_id uuid',
      ),
    );
    expect(sql, contains("'previous_result'"));
    expect(sql, contains("'random_no_history'"));
    expect(
      sql,
      contains('references public.omok_sessions(id)'),
    );
    expect(sql, contains('on delete set null'));
    expect(sql, isNot(contains('update public.omok_sessions set')));
  });

  test('가장 최근 확정 승패의 승자는 백돌이고 패자는 흑돌이다', () {
    expect(
      sql,
      contains(
        'create or replace function public.resolve_omok_stone_assignment',
      ),
    );
    expect(sql, contains('session.finished_at is not null'));
    expect(sql, contains('session.winner_user_id in'));
    expect(sql, contains("'black_timeout_win'"));
    expect(sql, contains("'white_resign_win'"));
    expect(sql, isNot(contains("session.status = 'draw'")));
    expect(
      sql,
      contains(
        'session.finished_at desc,\n    session.created_at desc,\n'
        '    session.id desc',
      ),
    );
    expect(
      sql,
      contains(
        'source_session.winner_user_id,\n'
        "      'previous_result'::text,\n"
        '      source_session.id',
      ),
    );
    expect(
      sql,
      contains(
        'when source_session.winner_user_id = target_player_a_user_id\n'
        '          then target_player_b_user_id',
      ),
    );
  });

  test('확정 승패가 없으면 서버 난수로 한 번만 배정한다', () {
    expect(sql, contains('extensions.gen_random_bytes(1)'));
    expect(sql, contains('pg_catalog.get_byte'));
    expect(
      sql,
      contains(
        "'random_no_history'::text,\n"
        '      null::uuid',
      ),
    );
    expect(sql, isNot(contains('dart:math')));
  });

  test('모든 대국 생성 경로는 중앙 세션 생성 함수를 사용한다', () {
    for (final functionName in [
      'join_omok_with_invite_code',
      'accept_omok_push_invite',
      'create_omok_rematch',
    ]) {
      expect(
        sql,
        contains('create or replace function public.$functionName'),
      );
    }

    expect(
      RegExp(
        r'created_session_id := public\.create_omok_session_internal\(',
      ).allMatches(sql).length,
      3,
    );
    expect(sql, contains('resolved_black_user_id'));
    expect(
      sql,
      contains('current_turn_user_id,\n    status'),
    );
    expect(
      sql,
      contains(
        'resolved_black_user_id,\n'
        '    resolved_white_user_id,\n'
        '    resolved_black_user_id',
      ),
    );
  });

  test('재대결의 잠금과 멱등성, RPC 권한 계약을 유지한다', () {
    expect(sql, contains('where session.id = target_session_id\n  for update'));
    expect(
      sql,
      contains('session.rematch_of_session_id = target_session_id'),
    );
    expect(sql, contains('return existing_session_id'));
    expect(sql, contains('pg_catalog.pg_advisory_xact_lock'));
    expect(
      sql,
      contains(
        'revoke all on function public.resolve_omok_stone_assignment',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on function public.create_omok_session_internal',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.join_omok_with_invite_code(text)',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.accept_omok_push_invite(uuid)',
      ),
    );
    expect(
      sql,
      contains('grant execute on function public.create_omok_rematch(uuid)'),
    );
    expect(sql, contains("notify pgrst, 'reload schema'"));
  });
}
