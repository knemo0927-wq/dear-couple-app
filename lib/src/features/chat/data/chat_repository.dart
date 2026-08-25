import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.coupleId,
    required this.senderId,
    required this.body,
    required this.imagePath,
    required this.createdAt,
    required this.heartCount,
    required this.isHeartedByMe,
    this.replyToMessageId,
  });

  final int id;
  final String coupleId;
  final String senderId;
  final String? body;
  final String? imagePath;
  final DateTime createdAt;
  final int heartCount;
  final bool isHeartedByMe;
  final int? replyToMessageId;

  bool get hasText => (body ?? '').trim().isNotEmpty;
  bool get hasImage => (imagePath ?? '').trim().isNotEmpty;

  ChatMessage copyWith({
    int? heartCount,
    bool? isHeartedByMe,
  }) {
    return ChatMessage(
      id: id,
      coupleId: coupleId,
      senderId: senderId,
      body: body,
      imagePath: imagePath,
      createdAt: createdAt,
      heartCount: heartCount ?? this.heartCount,
      isHeartedByMe: isHeartedByMe ?? this.isHeartedByMe,
      replyToMessageId: replyToMessageId,
    );
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as int,
      coupleId: map['couple_id'] as String,
      senderId: map['sender_id'] as String,
      body: map['body'] as String?,
      imagePath: map['image_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      heartCount: 0,
      isHeartedByMe: false,
      replyToMessageId: map['reply_to_message_id'] as int?,
    );
  }
}

class ChatMessagePage {
  const ChatMessagePage({
    required this.messages,
    required this.hasMore,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
}

class ChatReadMarker {
  const ChatReadMarker({
    required this.lastReadMessageId,
    required this.lastReadAt,
  });

  final int lastReadMessageId;
  final DateTime lastReadAt;
}

enum ChatImageSendOutcome { sent, cancelled, alreadySent }

class ChatRepository {
  ChatRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int initialPageSize = 30;
  static const String _messageColumns =
      'id,couple_id,sender_id,body,image_path,created_at,reply_to_message_id';

  /// Watches only the newest page and applies message/reaction changes
  /// incrementally through Supabase Realtime. Older pages are loaded explicitly
  /// with [fetchMessagesPage], so this stream never grows with chat history.
  Stream<List<ChatMessage>> watchMessages(String coupleId) async* {
    late final StreamController<List<ChatMessage>> controller;
    StreamSubscription<List<Map<String, dynamic>>>? messageSubscription;
    RealtimeChannel? reactionChannel;
    var latestRows = const <Map<String, dynamic>>[];
    var revision = 0;

    Future<void> emitLatest() async {
      final currentRevision = ++revision;
      try {
        final messages = _messagesFromRows(latestRows);
        final enriched = await _withReactionState(messages);
        if (!controller.isClosed && currentRevision == revision) {
          controller.add(List<ChatMessage>.unmodifiable(enriched));
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed && currentRevision == revision) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<List<ChatMessage>>(
      onListen: () {
        final stream = _client
            .from('messages')
            .stream(primaryKey: ['id'])
            .eq('couple_id', coupleId)
            .order('id', ascending: false)
            .limit(initialPageSize);

        messageSubscription = stream.listen(
          (rows) {
            latestRows = rows;
            emitLatest();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );

        reactionChannel = _client
            .channel(
              'chat-reactions-$coupleId-${DateTime.now().microsecondsSinceEpoch}',
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'message_reactions',
              callback: (payload) {
                final rawId = payload.newRecord['message_id'] ??
                    payload.oldRecord['message_id'];
                final messageId = rawId is int
                    ? rawId
                    : int.tryParse(rawId?.toString() ?? '');
                if (messageId == null) return;
                final containsMessage = latestRows.any(
                  (row) => row['id'] == messageId,
                );
                if (containsMessage) emitLatest();
              },
            )
            .subscribe();
      },
      onCancel: () async {
        revision += 1;
        await messageSubscription?.cancel();
        final channel = reactionChannel;
        if (channel != null) await _client.removeChannel(channel);
        await controller.close();
      },
    );

    yield* controller.stream;
  }

  Future<ChatMessagePage> fetchMessagesPage({
    required String coupleId,
    int? beforeMessageId,
    int limit = initialPageSize,
  }) async {
    var query = _client
        .from('messages')
        .select(_messageColumns)
        .eq('couple_id', coupleId);
    if (beforeMessageId != null) {
      query = query.lt('id', beforeMessageId);
    }
    final rows = await query.order('id', ascending: false).limit(limit);
    final messages = _messagesFromRows(rows);
    return ChatMessagePage(
      messages: List<ChatMessage>.unmodifiable(
        await _withReactionState(messages),
      ),
      hasMore: rows.length == limit,
    );
  }

  Future<List<ChatMessage>> searchMessages({
    required String coupleId,
    required String query,
    int limit = 100,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const <ChatMessage>[];
    final escapedQuery = normalizedQuery
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await _client
        .from('messages')
        .select(_messageColumns)
        .eq('couple_id', coupleId)
        .not('body', 'is', null)
        .ilike('body', '%$escapedQuery%')
        .order('id', ascending: false)
        .limit(limit);
    return List<ChatMessage>.unmodifiable(
      await _withReactionState(_messagesFromRows(rows).reversed.toList()),
    );
  }

  Future<ChatMessagePage> fetchMediaPage({
    required String coupleId,
    int? beforeMessageId,
    int limit = initialPageSize,
  }) async {
    var query = _client
        .from('messages')
        .select(_messageColumns)
        .eq('couple_id', coupleId)
        .not('image_path', 'is', null);
    if (beforeMessageId != null) {
      query = query.lt('id', beforeMessageId);
    }
    final rows = await query.order('id', ascending: false).limit(limit);
    return ChatMessagePage(
      messages: List<ChatMessage>.unmodifiable(
        await _withReactionState(_messagesFromRows(rows).reversed.toList()),
      ),
      hasMore: rows.length == limit,
    );
  }

  Future<String> createSignedChatImageUrl(String imagePath) {
    return _client.storage.from('chat-images').createSignedUrl(imagePath, 3600);
  }

  Future<ChatMessage?> fetchMessageById({
    required String coupleId,
    required int messageId,
  }) async {
    final rows = await _client
        .from('messages')
        .select(_messageColumns)
        .eq('couple_id', coupleId)
        .eq('id', messageId)
        .limit(1);
    if (rows.isEmpty) return null;
    final messages = await _withReactionState(_messagesFromRows(rows));
    return messages.isEmpty ? null : messages.first;
  }

  Stream<int> watchReactionMessageIds(String coupleId) {
    late final StreamController<int> controller;
    RealtimeChannel? channel;
    controller = StreamController<int>(
      onListen: () {
        channel = _client
            .channel(
              'chat-visible-reactions-$coupleId-'
              '${DateTime.now().microsecondsSinceEpoch}',
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'message_reactions',
              callback: (payload) {
                final rawId = payload.newRecord['message_id'] ??
                    payload.oldRecord['message_id'];
                final messageId = rawId is int
                    ? rawId
                    : int.tryParse(rawId?.toString() ?? '');
                if (messageId != null && !controller.isClosed) {
                  controller.add(messageId);
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        final currentChannel = channel;
        if (currentChannel != null) await _client.removeChannel(currentChannel);
        await controller.close();
      },
    );
    return controller.stream;
  }

  List<ChatMessage> _messagesFromRows(List<Map<String, dynamic>> rows) {
    final byId = <int, ChatMessage>{};
    for (final row in rows) {
      final message = ChatMessage.fromMap(row);
      byId[message.id] = message;
    }
    return byId.values.toList()
      ..sort((a, b) {
        final createdAt = a.createdAt.compareTo(b.createdAt);
        return createdAt != 0 ? createdAt : a.id.compareTo(b.id);
      });
  }

  Future<List<ChatMessage>> _withReactionState(
    List<ChatMessage> messages,
  ) async {
    final myUserId = _client.auth.currentUser?.id;
    if (messages.isEmpty || myUserId == null) return messages;

    final reactions = await _client
        .from('message_reactions')
        .select('message_id,user_id')
        .inFilter(
          'message_id',
          messages.map((message) => message.id).toList(growable: false),
        );
    final heartCountByMessageId = <int, int>{};
    final heartedByMeMessageIds = <int>{};
    for (final reaction in reactions) {
      final rawMessageId = reaction['message_id'];
      final messageId = rawMessageId is int
          ? rawMessageId
          : int.tryParse(rawMessageId?.toString() ?? '');
      if (messageId == null) continue;
      heartCountByMessageId[messageId] =
          (heartCountByMessageId[messageId] ?? 0) + 1;
      if (reaction['user_id'] == myUserId) {
        heartedByMeMessageIds.add(messageId);
      }
    }
    return messages
        .map(
          (message) => message.copyWith(
            heartCount: heartCountByMessageId[message.id] ?? 0,
            isHeartedByMe: heartedByMeMessageIds.contains(message.id),
          ),
        )
        .toList(growable: false);
  }

  Future<void> sendTextMessage({
    required String coupleId,
    required String text,
    int? replyToMessageId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }

    await _client.from('messages').insert({
      'couple_id': coupleId,
      'sender_id': user.id,
      'body': normalized,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
    });
  }

  Future<void> toggleHeartReaction({required int messageId}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final existing = await _client
        .from('message_reactions')
        .select('id')
        .eq('message_id', messageId)
        .eq('user_id', user.id)
        .eq('emoji', '❤️')
        .limit(1);

    if (existing.isNotEmpty) {
      final reactionId = existing.first['id'];
      await _client.from('message_reactions').delete().eq('id', reactionId);
      return;
    }

    await _client.from('message_reactions').insert({
      'message_id': messageId,
      'user_id': user.id,
      'emoji': '❤️',
    });
  }

  Future<void> deleteMessage(int messageId) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');
    final rows = await _client
        .from('messages')
        .select('image_path')
        .eq('id', messageId)
        .eq('sender_id', user.id)
        .limit(1);
    if (rows.isEmpty) return;
    final imagePath = rows.first['image_path']?.toString().trim();
    await _client
        .from('messages')
        .delete()
        .eq('id', messageId)
        .eq('sender_id', user.id);
    if (imagePath != null && imagePath.isNotEmpty) {
      try {
        await _client.storage.from('chat-images').remove([imagePath]);
      } catch (_) {
        // The database row is authoritative; orphan cleanup can be retried by
        // a maintenance job if object removal temporarily fails.
      }
    }
  }

  Future<void> sendImageMessage({
    required String coupleId,
    required Uint8List bytes,
    required String extension,
  }) async {
    await sendImageMessageWithControl(
      coupleId: coupleId,
      bytes: bytes,
      extension: extension,
      idempotencyKey:
          '${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(bytes)}',
      isCancelled: () => false,
    );
  }

  Future<ChatImageSendOutcome> sendImageMessageWithControl({
    required String coupleId,
    required Uint8List bytes,
    required String extension,
    required String idempotencyKey,
    required bool Function() isCancelled,
    void Function(double progress)? onProgress,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('AUTH_REQUIRED');
    }

    final ext = extension.toLowerCase().replaceAll('.', '');
    final safeKey = idempotencyKey.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
    final imagePath = '$coupleId/${user.id}_$safeKey.$ext';

    final existing = await _client
        .from('messages')
        .select('id')
        .eq('couple_id', coupleId)
        .eq('image_path', imagePath)
        .limit(1);
    if (existing.isNotEmpty) return ChatImageSendOutcome.alreadySent;
    if (isCancelled()) return ChatImageSendOutcome.cancelled;

    onProgress?.call(0.1);
    await _client.storage.from('chat-images').uploadBinary(
          imagePath,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    onProgress?.call(0.75);

    if (isCancelled()) {
      await _client.storage.from('chat-images').remove([imagePath]);
      return ChatImageSendOutcome.cancelled;
    }

    final duplicateCheck = await _client
        .from('messages')
        .select('id')
        .eq('couple_id', coupleId)
        .eq('image_path', imagePath)
        .limit(1);
    if (duplicateCheck.isEmpty) {
      await _client.from('messages').insert({
        'couple_id': coupleId,
        'sender_id': user.id,
        'image_path': imagePath,
      });
    }
    onProgress?.call(1);
    return duplicateCheck.isEmpty
        ? ChatImageSendOutcome.sent
        : ChatImageSendOutcome.alreadySent;
  }

  Future<ChatReadMarker?> fetchReadMarker(String coupleId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final rows = await _client
        .from('conversation_reads')
        .select('last_read_message_id,last_read_at')
        .eq('couple_id', coupleId)
        .eq('user_id', user.id)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final rawId = row['last_read_message_id'];
    final messageId =
        rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final readAt = DateTime.tryParse(row['last_read_at']?.toString() ?? '');
    if (messageId == null || readAt == null) return null;
    return ChatReadMarker(
      lastReadMessageId: messageId,
      lastReadAt: readAt,
    );
  }

  Stream<ChatReadMarker?> watchPartnerReadMarker(String coupleId) {
    final user = _client.auth.currentUser;
    if (user == null) return Stream<ChatReadMarker?>.value(null);
    return _client
        .from('conversation_reads')
        .stream(primaryKey: ['couple_id', 'user_id'])
        .eq('couple_id', coupleId)
        .map((rows) {
          ChatReadMarker? latest;
          for (final row in rows) {
            if (row['user_id'] == user.id) continue;
            final rawId = row['last_read_message_id'];
            final messageId =
                rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
            final readAt =
                DateTime.tryParse(row['last_read_at']?.toString() ?? '');
            if (messageId == null || readAt == null) continue;
            if (latest == null || messageId > latest.lastReadMessageId) {
              latest = ChatReadMarker(
                lastReadMessageId: messageId,
                lastReadAt: readAt,
              );
            }
          }
          return latest;
        });
  }

  Stream<int> watchUnreadCount({
    required String coupleId,
    required String myUserId,
    required int lastReadMessageId,
  }) {
    late final StreamController<int> controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final count = await _client
            .from('messages')
            .count(CountOption.exact)
            .eq('couple_id', coupleId)
            .neq('sender_id', myUserId)
            .gt('id', lastReadMessageId);
        if (!controller.isClosed) controller.add(count);
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<int>(
      onListen: () {
        refresh();
        channel = _client
            .channel(
              'chat-unread-$coupleId-$myUserId-'
              '${DateTime.now().microsecondsSinceEpoch}',
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'couple_id',
                value: coupleId,
              ),
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () async {
        final currentChannel = channel;
        if (currentChannel != null) await _client.removeChannel(currentChannel);
        await controller.close();
      },
    );
    return controller.stream;
  }

  Stream<bool> watchPartnerOnline(String coupleId) {
    final user = _client.auth.currentUser;
    if (user == null) return Stream<bool>.value(false);
    late final StreamController<bool> controller;
    late final RealtimeChannel channel;

    void emitPresence() {
      final isPartnerOnline = channel.presenceState().any(
            (state) => state.presences.any(
              (presence) => presence.payload['user_id'] != user.id,
            ),
          );
      if (!controller.isClosed) controller.add(isPartnerOnline);
    }

    controller = StreamController<bool>(
      onListen: () {
        channel = _client.channel(
          'couple-presence-$coupleId',
          opts: RealtimeChannelConfig(key: user.id),
        );
        channel
            .onPresenceSync((_) => emitPresence())
            .onPresenceJoin((_) => emitPresence())
            .onPresenceLeave((_) => emitPresence())
            .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            channel.track({
              'user_id': user.id,
              'online_at': DateTime.now().toUtc().toIso8601String(),
            });
            emitPresence();
          }
        });
      },
      onCancel: () async {
        await channel.untrack();
        await _client.removeChannel(channel);
        await controller.close();
      },
    );
    return controller.stream;
  }

  Future<void> markConversationRead({
    required String coupleId,
    required int lastReadMessageId,
    required DateTime lastReadAt,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('AUTH_REQUIRED');
    await _client.from('conversation_reads').upsert(
      {
        'couple_id': coupleId,
        'user_id': user.id,
        'last_read_message_id': lastReadMessageId,
        'last_read_at': lastReadAt.toUtc().toIso8601String(),
      },
      onConflict: 'couple_id,user_id',
    );
  }
}
