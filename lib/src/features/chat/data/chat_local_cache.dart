import 'dart:convert';

import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int chatRecentMessageCacheLimit = 30;

class ChatReadLocalState {
  const ChatReadLocalState({
    required this.marker,
    required this.syncPending,
  });

  final ChatReadMarker marker;
  final bool syncPending;
}

abstract interface class ChatRecentMessageCache {
  Future<List<ChatMessage>> read({
    required String ownerId,
    required String coupleId,
  });

  Future<void> write({
    required String ownerId,
    required String coupleId,
    required List<ChatMessage> messages,
  });
}

class SharedPreferencesChatLocalStore implements ChatRecentMessageCache {
  const SharedPreferencesChatLocalStore();

  String _readMarkerKey(String ownerId, String coupleId) =>
      'chat_read_marker_v2_${_keyPart(ownerId)}_${_keyPart(coupleId)}';

  String _recentMessagesKey(String ownerId, String coupleId) =>
      'chat_recent_messages_v1_${_keyPart(ownerId)}_${_keyPart(coupleId)}';

  String _keyPart(String value) => base64Url.encode(utf8.encode(value.trim()));

  Future<ChatReadLocalState?> readReadMarker({
    required String ownerId,
    required String coupleId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_readMarkerKey(ownerId, coupleId));
    if (raw == null || raw.isEmpty) {
      final legacyAtKey = 'chat_last_read_$coupleId';
      final legacyIdKey = 'chat_last_read_message_id_$coupleId';
      final legacyAt = DateTime.tryParse(prefs.getString(legacyAtKey) ?? '');
      final legacyId = prefs.getInt(legacyIdKey);
      if (legacyAt == null || legacyId == null || legacyId <= 0) return null;
      final migrated = ChatReadLocalState(
        marker: ChatReadMarker(
          lastReadMessageId: legacyId,
          lastReadAt: legacyAt.toUtc(),
        ),
        syncPending: true,
      );
      await prefs.setString(
        _readMarkerKey(ownerId, coupleId),
        jsonEncode({
          'lastReadMessageId': migrated.marker.lastReadMessageId,
          'lastReadAt': migrated.marker.lastReadAt.toIso8601String(),
          'syncPending': true,
        }),
      );
      await prefs.remove(legacyAtKey);
      await prefs.remove(legacyIdKey);
      return migrated;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final rawId = decoded['lastReadMessageId'];
      final messageId =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      final readAt = DateTime.tryParse(decoded['lastReadAt']?.toString() ?? '');
      if (messageId == null || messageId <= 0 || readAt == null) return null;
      return ChatReadLocalState(
        marker: ChatReadMarker(
          lastReadMessageId: messageId,
          lastReadAt: readAt.toUtc(),
        ),
        syncPending: decoded['syncPending'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeReadMarker({
    required String ownerId,
    required String coupleId,
    required ChatReadLocalState state,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _readMarkerKey(ownerId, coupleId),
      jsonEncode({
        'lastReadMessageId': state.marker.lastReadMessageId,
        'lastReadAt': state.marker.lastReadAt.toUtc().toIso8601String(),
        'syncPending': state.syncPending,
      }),
    );
  }

  @override
  Future<List<ChatMessage>> read({
    required String ownerId,
    required String coupleId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentMessagesKey(ownerId, coupleId));
    if (raw == null || raw.isEmpty) return const <ChatMessage>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        return const <ChatMessage>[];
      }
      final rawMessages = decoded['messages'];
      if (rawMessages is! List) return const <ChatMessage>[];
      final messages = <ChatMessage>[];
      for (final rawMessage in rawMessages) {
        final message = _decodeMessage(rawMessage, expectedCoupleId: coupleId);
        if (message != null) messages.add(message);
      }
      return _boundedMessages(messages, coupleId: coupleId);
    } catch (_) {
      return const <ChatMessage>[];
    }
  }

  @override
  Future<void> write({
    required String ownerId,
    required String coupleId,
    required List<ChatMessage> messages,
  }) async {
    final bounded = _boundedMessages(messages, coupleId: coupleId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recentMessagesKey(ownerId, coupleId),
      jsonEncode({
        'version': 1,
        'messages': bounded.map(_encodeMessage).toList(growable: false),
      }),
    );
  }

  List<ChatMessage> _boundedMessages(
    Iterable<ChatMessage> messages, {
    required String coupleId,
  }) {
    final byId = <int, ChatMessage>{};
    for (final message in messages) {
      if (message.id <= 0 || message.coupleId != coupleId) continue;
      byId[message.id] = message;
    }
    final sorted = byId.values.toList()
      ..sort((a, b) {
        final date = a.createdAt.compareTo(b.createdAt);
        return date != 0 ? date : a.id.compareTo(b.id);
      });
    if (sorted.length <= chatRecentMessageCacheLimit) {
      return List<ChatMessage>.unmodifiable(sorted);
    }
    return List<ChatMessage>.unmodifiable(
      sorted.sublist(sorted.length - chatRecentMessageCacheLimit),
    );
  }

  Map<String, Object?> _encodeMessage(ChatMessage message) => {
        'id': message.id,
        'coupleId': message.coupleId,
        'senderId': message.senderId,
        'body': message.body,
        'imagePath': message.imagePath,
        'createdAt': message.createdAt.toUtc().toIso8601String(),
        'heartCount': message.heartCount,
        'isHeartedByMe': message.isHeartedByMe,
        'replyToMessageId': message.replyToMessageId,
      };

  ChatMessage? _decodeMessage(
    Object? value, {
    required String expectedCoupleId,
  }) {
    if (value is! Map<String, dynamic>) return null;
    final rawId = value['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final coupleId = value['coupleId']?.toString();
    final senderId = value['senderId']?.toString();
    final createdAt = DateTime.tryParse(value['createdAt']?.toString() ?? '');
    if (id == null ||
        id <= 0 ||
        coupleId != expectedCoupleId ||
        senderId == null ||
        senderId.isEmpty ||
        createdAt == null) {
      return null;
    }
    final rawHeartCount = value['heartCount'];
    final heartCount = rawHeartCount is int
        ? rawHeartCount
        : int.tryParse(rawHeartCount?.toString() ?? '') ?? 0;
    final rawReplyId = value['replyToMessageId'];
    final replyId = rawReplyId is int
        ? rawReplyId
        : int.tryParse(rawReplyId?.toString() ?? '');
    return ChatMessage(
      id: id,
      coupleId: coupleId!,
      senderId: senderId,
      body: value['body'] is String ? value['body'] as String : null,
      imagePath:
          value['imagePath'] is String ? value['imagePath'] as String : null,
      createdAt: createdAt.toUtc(),
      heartCount: heartCount < 0 ? 0 : heartCount,
      isHeartedByMe: value['isHeartedByMe'] == true,
      replyToMessageId: replyId,
    );
  }
}
