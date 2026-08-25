import 'dart:async';
import 'dart:io';

import 'package:couple_chat_app/src/features/chat/data/chat_local_cache.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _coupleId = '11111111-1111-4111-8111-111111111111';
const _ownerId = 'user-1';

ChatMessage _message(int id, {String senderId = 'user-2'}) => ChatMessage(
      id: id,
      coupleId: _coupleId,
      senderId: senderId,
      body: '메시지 $id',
      imagePath: id.isEven ? 'chat/$id.jpg' : null,
      createdAt: DateTime.utc(2026, 7, 12, 9, 0, id),
      heartCount: id % 3,
      isHeartedByMe: id.isEven,
      replyToMessageId: id > 1 ? id - 1 : null,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('remote 실패를 다시 던지면서 local max cursor를 pending으로 보존한다', () async {
    var shouldFail = true;
    var remoteMarker = ChatReadMarker(
      lastReadMessageId: 10,
      lastReadAt: DateTime.utc(2026, 7, 12, 9, 0, 10),
    );
    final container = ProviderContainer(
      overrides: [
        chatCurrentUserIdProvider.overrideWithValue(_ownerId),
        chatFetchReadMarkerProvider
            .overrideWithValue((_) async => remoteMarker),
        chatRemoteMarkReadProvider.overrideWithValue(({
          required coupleId,
          required lastReadMessageId,
          required lastReadAt,
        }) async {
          if (shouldFail) throw StateError('offline');
          remoteMarker = ChatReadMarker(
            lastReadMessageId: lastReadMessageId,
            lastReadAt: lastReadAt,
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final action = container.read(chatMarkReadProvider);
    await expectLater(
      action(
        coupleId: _coupleId,
        lastReadMessageId: 11,
        lastReadAt: DateTime.utc(2026, 7, 12, 9, 0, 11),
      ),
      throwsStateError,
    );

    final merged =
        await container.read(chatReadMarkerProvider(_coupleId).future);
    expect(merged?.lastReadMessageId, 11);
    final local = await container.read(chatLocalStoreProvider).readReadMarker(
          ownerId: _ownerId,
          coupleId: _coupleId,
        );
    expect(local?.marker.lastReadMessageId, 11);
    expect(local?.syncPending, isTrue);

    shouldFail = false;
    await action(
      coupleId: _coupleId,
      lastReadMessageId: 11,
      lastReadAt: DateTime.utc(2026, 7, 12, 9, 0, 11),
    );
    final synced = await container.read(chatLocalStoreProvider).readReadMarker(
          ownerId: _ownerId,
          coupleId: _coupleId,
        );
    expect(synced?.marker.lastReadMessageId, 11);
    expect(synced?.syncPending, isFalse);
  });

  test('couple별 remote write를 직렬화하고 낮은 후속 cursor를 건너뛴다', () async {
    final firstCompleter = Completer<void>();
    final remoteIds = <int>[];
    final container = ProviderContainer(
      overrides: [
        chatCurrentUserIdProvider.overrideWithValue(_ownerId),
        chatFetchReadMarkerProvider.overrideWithValue((_) async => null),
        chatRemoteMarkReadProvider.overrideWithValue(({
          required coupleId,
          required lastReadMessageId,
          required lastReadAt,
        }) async {
          remoteIds.add(lastReadMessageId);
          if (remoteIds.length == 1) await firstCompleter.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    final action = container.read(chatMarkReadProvider);

    final mark11 = action(
      coupleId: _coupleId,
      lastReadMessageId: 11,
      lastReadAt: DateTime.utc(2026, 7, 12, 9, 0, 11),
    );
    final mark10 = action(
      coupleId: _coupleId,
      lastReadMessageId: 10,
      lastReadAt: DateTime.utc(2026, 7, 12, 9, 0, 10),
    );
    await Future<void>.delayed(Duration.zero);
    expect(remoteIds, [11]);

    firstCompleter.complete();
    await Future.wait([mark11, mark10]);
    expect(remoteIds, [11]);
    final local = await container.read(chatLocalStoreProvider).readReadMarker(
          ownerId: _ownerId,
          coupleId: _coupleId,
        );
    expect(local?.marker.lastReadMessageId, 11);
    expect(local?.syncPending, isFalse);
  });

  test('write 응답이 실패해도 서버 canonical이 앞서면 동기화 성공으로 복구한다', () async {
    final canonical = ChatReadMarker(
      lastReadMessageId: 12,
      lastReadAt: DateTime.utc(2026, 7, 12, 9, 0, 12),
    );
    final container = ProviderContainer(
      overrides: [
        chatCurrentUserIdProvider.overrideWithValue(_ownerId),
        chatFetchReadMarkerProvider.overrideWithValue((_) async => canonical),
        chatRemoteMarkReadProvider.overrideWithValue(({
          required coupleId,
          required lastReadMessageId,
          required lastReadAt,
        }) async {
          throw StateError('response lost');
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(chatMarkReadProvider)(
      coupleId: _coupleId,
      lastReadMessageId: 11,
      lastReadAt: DateTime.utc(2026, 7, 12, 9, 0, 11),
    );
    final local = await container.read(chatLocalStoreProvider).readReadMarker(
          ownerId: _ownerId,
          coupleId: _coupleId,
        );
    expect(local?.marker.lastReadMessageId, 12);
    expect(local?.syncPending, isFalse);
  });

  test('기존 두 prefs key를 사용자별 단일 marker로 한 번만 이전한다', () async {
    SharedPreferences.setMockInitialValues({
      'chat_last_read_$_coupleId':
          DateTime.utc(2026, 7, 12, 9).toIso8601String(),
      'chat_last_read_message_id_$_coupleId': 9,
    });
    const store = SharedPreferencesChatLocalStore();
    final migrated =
        await store.readReadMarker(ownerId: _ownerId, coupleId: _coupleId);
    expect(migrated?.marker.lastReadMessageId, 9);
    expect(migrated?.syncPending, isTrue);
    expect(
      await store.readReadMarker(
        ownerId: 'other-user',
        coupleId: _coupleId,
      ),
      isNull,
    );
  });

  test('최근 메시지 캐시는 사용자별로 마지막 30개만 직렬화한다', () async {
    const cache = SharedPreferencesChatLocalStore();
    await cache.write(
      ownerId: _ownerId,
      coupleId: _coupleId,
      messages: [for (var id = 1; id <= 35; id++) _message(id)],
    );

    final restored = await cache.read(ownerId: _ownerId, coupleId: _coupleId);
    expect(restored, hasLength(chatRecentMessageCacheLimit));
    expect(restored.first.id, 6);
    expect(restored.last.id, 35);
    expect(restored.last.body, '메시지 35');
    expect(restored.last.replyToMessageId, 34);
    expect(
      await cache.read(ownerId: 'other-user', coupleId: _coupleId),
      isEmpty,
    );
  });

  test('오프라인 캐시를 먼저 내고 재연결 서버 snapshot으로 canonical 갱신한다', () async {
    const cache = SharedPreferencesChatLocalStore();
    await cache.write(
      ownerId: _ownerId,
      coupleId: _coupleId,
      messages: [_message(1)],
    );
    var attempts = 0;
    final snapshots = await watchChatMessagesWithCache(
      ownerId: _ownerId,
      coupleId: _coupleId,
      cache: cache,
      retryDelay: Duration.zero,
      watchRemote: () {
        attempts += 1;
        if (attempts == 1) {
          return Stream<List<ChatMessage>>.error(StateError('offline'));
        }
        return Stream<List<ChatMessage>>.value([_message(2)]);
      },
    ).take(2).toList();

    expect(snapshots[0].single.id, 1);
    expect(snapshots[1].single.id, 2);
    expect(attempts, 2);
    final canonical = await cache.read(ownerId: _ownerId, coupleId: _coupleId);
    expect(canonical.single.id, 2);
  });

  test('conversation_reads migration은 cursor 단조성과 사용자 ACL을 고정한다', () {
    final sql = File(
      'supabase/migrations/202607120001_dear_product_audit_foundation.sql',
    ).readAsStringSync();
    expect(sql, contains('READ_CURSOR_MUST_BE_MONOTONIC'));
    expect(
      sql,
      contains('new.last_read_message_id < old.last_read_message_id'),
    );
    expect(sql, contains('conversation_reads_select_couple'));
    expect(sql, contains('conversation_reads_insert_own'));
    expect(sql, contains('conversation_reads_update_own'));
    expect(sql, contains('user_id = auth.uid()'));
  });
}
