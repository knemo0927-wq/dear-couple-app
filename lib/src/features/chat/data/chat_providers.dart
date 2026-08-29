import 'dart:typed_data';

import 'package:couple_chat_app/src/features/chat/data/chat_local_cache.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ChatWatchMessages = Stream<List<ChatMessage>> Function(String coupleId);
typedef ChatSendTextAction = Future<void> Function({
  required String coupleId,
  required String text,
});
typedef ChatSendReplyTextAction = Future<void> Function({
  required String coupleId,
  required String text,
  int? replyToMessageId,
});
typedef ChatSendImageAction = Future<void> Function({
  required String coupleId,
  required Uint8List bytes,
  required String extension,
});
typedef ChatUploadImageAction = Future<ChatImageSendOutcome> Function({
  required String coupleId,
  required Uint8List bytes,
  required String extension,
  required String idempotencyKey,
  required bool Function() isCancelled,
  void Function(double progress)? onProgress,
});
typedef ChatFetchMessagesPage = Future<ChatMessagePage> Function({
  required String coupleId,
  int? beforeMessageId,
  int limit,
});
typedef ChatSearchMessages = Future<List<ChatMessage>> Function({
  required String coupleId,
  required String query,
  int limit,
});
typedef ChatFetchMediaPage = Future<ChatMessagePage> Function({
  required String coupleId,
  int? beforeMessageId,
  int limit,
});
typedef ChatResolveImageUrl = Future<String> Function(String imagePath);
typedef ChatFetchMessageById = Future<ChatMessage?> Function({
  required String coupleId,
  required int messageId,
});
typedef ChatWatchReactionMessageIds = Stream<int> Function(String coupleId);
typedef ChatPickImageAction = Future<PickedChatImage?> Function();
typedef ChatPickImagesAction = Future<List<PickedChatImage>> Function();
typedef ChatMarkReadAction = Future<void> Function({
  required String coupleId,
  required int lastReadMessageId,
  required DateTime lastReadAt,
});
typedef ChatFetchReadMarkerAction = Future<ChatReadMarker?> Function(
  String coupleId,
);
typedef ChatToggleReactionAction = Future<void> Function({
  required int messageId,
});
typedef ChatAddHeartReactionAction = Future<void> Function({
  required int messageId,
});
typedef ChatDeleteMessageAction = Future<void> Function(int messageId);

const int chatImageWarningBytes = 5 * 1024 * 1024;
const int chatImageMaxBytes = 8 * 1024 * 1024;
const Set<String> chatAllowedImageExtensions = {'jpg', 'png', 'webp'};

bool isImageSizeWarning(int bytes) => bytes > chatImageWarningBytes;
bool isImageTooLarge(int bytes) => bytes > chatImageMaxBytes;

String normalizeImageExtension(String extension) {
  final normalized = extension.trim().toLowerCase().replaceAll('.', '');
  if (normalized == 'jpeg') {
    return 'jpg';
  }
  return normalized;
}

bool isSupportedImageExtension(String extension) {
  final normalized = normalizeImageExtension(extension);
  return chatAllowedImageExtensions.contains(normalized);
}

String formatImageSizeLabel(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

String resolveImageExtension(String filename) {
  final dotIndex = filename.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex >= filename.length - 1) {
    return 'jpg';
  }

  final extension = normalizeImageExtension(
    filename.substring(dotIndex + 1),
  );
  if (extension.isEmpty) {
    return 'jpg';
  }
  return extension;
}

class PickedChatImage {
  const PickedChatImage({
    required this.bytes,
    required this.extension,
  });

  final Uint8List bytes;
  final String extension;
}

final chatRepositoryProvider =
    Provider<ChatRepository>((ref) => ChatRepository());

final chatLocalStoreProvider = Provider<SharedPreferencesChatLocalStore>(
  (ref) => const SharedPreferencesChatLocalStore(),
);

Stream<List<ChatMessage>> watchChatMessagesWithCache({
  required String ownerId,
  required String coupleId,
  required Stream<List<ChatMessage>> Function() watchRemote,
  required ChatRecentMessageCache cache,
  Duration retryDelay = const Duration(seconds: 2),
}) async* {
  var hasUsableSnapshot = false;
  var retryAttempt = 0;
  try {
    final cached = await cache.read(ownerId: ownerId, coupleId: coupleId);
    if (cached.isNotEmpty) {
      hasUsableSnapshot = true;
      yield cached;
    }
  } catch (_) {
    // A damaged local cache must never prevent the canonical stream loading.
  }

  while (true) {
    var receivedRemoteSnapshot = false;
    try {
      await for (final remoteMessages in watchRemote()) {
        receivedRemoteSnapshot = true;
        retryAttempt = 0;
        hasUsableSnapshot = true;
        try {
          await cache.write(
            ownerId: ownerId,
            coupleId: coupleId,
            messages: remoteMessages,
          );
        } catch (_) {
          // The server snapshot remains usable even if local persistence fails.
        }
        yield List<ChatMessage>.unmodifiable(remoteMessages);
      }
    } catch (error, stackTrace) {
      if (!hasUsableSnapshot) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }

    if (!receivedRemoteSnapshot) {
      retryAttempt = (retryAttempt + 1).clamp(0, 4);
    }
    final multiplier = 1 << (retryAttempt == 0 ? 0 : retryAttempt - 1);
    final retryMilliseconds =
        (retryDelay.inMilliseconds * multiplier).clamp(0, 15000);
    await Future<void>.delayed(Duration(milliseconds: retryMilliseconds));
  }
}

final chatWatchMessagesProvider = Provider<ChatWatchMessages>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  final ownerId = ref.watch(chatCurrentUserIdProvider);
  if (ownerId == null) return repository.watchMessages;
  final cache = ref.watch(chatLocalStoreProvider);
  return (coupleId) => watchChatMessagesWithCache(
        ownerId: ownerId,
        coupleId: coupleId,
        watchRemote: () => repository.watchMessages(coupleId),
        cache: cache,
      );
});

final chatSendTextProvider = Provider<ChatSendTextAction>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({required coupleId, required text}) =>
      repository.sendTextMessage(coupleId: coupleId, text: text);
});

final chatSendReplyTextProvider = Provider<ChatSendReplyTextAction>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({required coupleId, required text, replyToMessageId}) =>
      repository.sendTextMessage(
        coupleId: coupleId,
        text: text,
        replyToMessageId: replyToMessageId,
      );
});

final chatSendImageProvider = Provider<ChatSendImageAction>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({required coupleId, required bytes, required extension}) =>
      repository.sendImageMessage(
        coupleId: coupleId,
        bytes: bytes,
        extension: extension,
      );
});

final chatUploadImageProvider = Provider<ChatUploadImageAction>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({
    required coupleId,
    required bytes,
    required extension,
    required idempotencyKey,
    required isCancelled,
    onProgress,
  }) {
    return repository.sendImageMessageWithControl(
      coupleId: coupleId,
      bytes: bytes,
      extension: extension,
      idempotencyKey: idempotencyKey,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  };
});

final chatFetchMessagesPageProvider = Provider<ChatFetchMessagesPage>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({
    required String coupleId,
    int? beforeMessageId,
    int limit = ChatRepository.initialPageSize,
  }) {
    return repository.fetchMessagesPage(
      coupleId: coupleId,
      beforeMessageId: beforeMessageId,
      limit: limit,
    );
  };
});

final chatSearchMessagesProvider = Provider<ChatSearchMessages>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({required coupleId, required query, int limit = 100}) {
    return repository.searchMessages(
      coupleId: coupleId,
      query: query,
      limit: limit,
    );
  };
});

final chatFetchMediaPageProvider = Provider<ChatFetchMediaPage>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({
    required coupleId,
    beforeMessageId,
    int limit = ChatRepository.initialPageSize,
  }) {
    return repository.fetchMediaPage(
      coupleId: coupleId,
      beforeMessageId: beforeMessageId,
      limit: limit,
    );
  };
});

final chatResolveImageUrlProvider = Provider<ChatResolveImageUrl>((ref) {
  return ref.watch(chatRepositoryProvider).createSignedChatImageUrl;
});

final chatFetchMessageByIdProvider = Provider<ChatFetchMessageById>((ref) {
  return ref.watch(chatRepositoryProvider).fetchMessageById;
});

final chatWatchReactionMessageIdsProvider =
    Provider<ChatWatchReactionMessageIds>((ref) {
  return (coupleId) async* {
    try {
      yield* ref.read(chatRepositoryProvider).watchReactionMessageIds(coupleId);
    } catch (_) {
      return;
    }
  };
});

final chatToggleReactionProvider = Provider<ChatToggleReactionAction>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({required messageId}) =>
      repository.toggleHeartReaction(messageId: messageId);
});

final chatAddHeartReactionProvider =
    Provider<ChatAddHeartReactionAction>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return ({required messageId}) =>
      repository.addHeartReaction(messageId: messageId);
});

final chatDeleteMessageProvider = Provider<ChatDeleteMessageAction>((ref) {
  return ref.watch(chatRepositoryProvider).deleteMessage;
});

final chatPickImageProvider = Provider<ChatPickImageAction>((ref) {
  final picker = ImagePicker();
  return () async {
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    final filename = picked.name;
    final extension = resolveImageExtension(filename);

    return PickedChatImage(bytes: bytes, extension: extension);
  };
});

final chatPickImagesProvider = Provider<ChatPickImagesAction>((ref) {
  final picker = ImagePicker();
  return () async {
    final pickedList = await picker.pickMultiImage(imageQuality: 85);
    if (pickedList.isEmpty) return const <PickedChatImage>[];

    final images = <PickedChatImage>[];
    for (final picked in pickedList) {
      final bytes = await picked.readAsBytes();
      final extension = resolveImageExtension(picked.name);
      images.add(PickedChatImage(bytes: bytes, extension: extension));
    }
    return images;
  };
});

final chatCurrentUserIdProvider = Provider<String?>((ref) {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    return null;
  }
});

class ChatConversationPreview {
  const ChatConversationPreview({
    required this.text,
    required this.createdAt,
  });

  final String text;
  final DateTime createdAt;
}

final chatFetchReadMarkerProvider = Provider<ChatFetchReadMarkerAction>((ref) {
  return ref.watch(chatRepositoryProvider).fetchReadMarker;
});

final chatRemoteMarkReadProvider = Provider<ChatMarkReadAction>((ref) {
  return ({
    required coupleId,
    required lastReadMessageId,
    required lastReadAt,
  }) {
    return ref.read(chatRepositoryProvider).markConversationRead(
          coupleId: coupleId,
          lastReadMessageId: lastReadMessageId,
          lastReadAt: lastReadAt,
        );
  };
});

final chatReadMarkerProvider =
    FutureProvider.family<ChatReadMarker?, String>((ref, coupleId) async {
  final ownerId = ref.watch(chatCurrentUserIdProvider);
  final store = ref.watch(chatLocalStoreProvider);
  final local = ownerId == null
      ? null
      : await store.readReadMarker(ownerId: ownerId, coupleId: coupleId);

  ChatReadMarker? remote;
  try {
    remote = await ref.watch(chatFetchReadMarkerProvider)(coupleId);
  } catch (_) {
    return local?.marker;
  }

  if (remote == null) return local?.marker;
  if (local != null &&
      local.marker.lastReadMessageId > remote.lastReadMessageId) {
    return local.marker;
  }

  if (ownerId != null) {
    try {
      await store.writeReadMarker(
        ownerId: ownerId,
        coupleId: coupleId,
        state: ChatReadLocalState(marker: remote, syncPending: false),
      );
    } catch (_) {
      // A canonical remote cursor is still valid if local persistence fails.
    }
  }
  return remote;
});

final chatLastReadAtProvider =
    FutureProvider.family<DateTime?, String>((ref, coupleId) async {
  final marker = await ref.watch(chatReadMarkerProvider(coupleId).future);
  return marker?.lastReadAt.toUtc();
});

final chatPartnerReadMarkerProvider =
    StreamProvider.family<ChatReadMarker?, String>((ref, coupleId) async* {
  try {
    final repository = ref.read(chatRepositoryProvider);
    yield* repository.watchPartnerReadMarker(coupleId);
  } catch (_) {
    yield null;
  }
});

final chatMarkReadProvider = Provider<ChatMarkReadAction>((ref) {
  final ownerId = ref.watch(chatCurrentUserIdProvider);
  final store = ref.watch(chatLocalStoreProvider);
  final markRemote = ref.watch(chatRemoteMarkReadProvider);
  final fetchRemote = ref.watch(chatFetchReadMarkerProvider);
  final queueTailByCouple = <String, Future<void>>{};

  Future<void> perform({
    required String coupleId,
    required int lastReadMessageId,
    required DateTime lastReadAt,
  }) async {
    if (ownerId == null) {
      return markRemote(
        coupleId: coupleId,
        lastReadMessageId: lastReadMessageId,
        lastReadAt: lastReadAt,
      );
    }

    final local = await store.readReadMarker(
      ownerId: ownerId,
      coupleId: coupleId,
    );
    final requestedMarker = ChatReadMarker(
      lastReadMessageId: lastReadMessageId,
      lastReadAt: lastReadAt.toUtc(),
    );
    final target = local != null &&
            local.marker.lastReadMessageId > requestedMarker.lastReadMessageId
        ? local.marker
        : requestedMarker;

    if (local != null &&
        !local.syncPending &&
        target.lastReadMessageId <= local.marker.lastReadMessageId) {
      return;
    }

    await store.writeReadMarker(
      ownerId: ownerId,
      coupleId: coupleId,
      state: ChatReadLocalState(marker: target, syncPending: true),
    );
    ref.invalidate(chatReadMarkerProvider(coupleId));
    ref.invalidate(chatLastReadAtProvider(coupleId));

    try {
      await markRemote(
        coupleId: coupleId,
        lastReadMessageId: target.lastReadMessageId,
        lastReadAt: target.lastReadAt,
      );
      await store.writeReadMarker(
        ownerId: ownerId,
        coupleId: coupleId,
        state: ChatReadLocalState(marker: target, syncPending: false),
      );
    } catch (error, stackTrace) {
      try {
        final canonical = await fetchRemote(coupleId);
        if (canonical != null &&
            canonical.lastReadMessageId >= target.lastReadMessageId) {
          await store.writeReadMarker(
            ownerId: ownerId,
            coupleId: coupleId,
            state: ChatReadLocalState(
              marker: canonical,
              syncPending: false,
            ),
          );
          return;
        }
      } catch (_) {
        // Preserve the original write failure when canonical fetch also fails.
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      ref.invalidate(chatReadMarkerProvider(coupleId));
      ref.invalidate(chatLastReadAtProvider(coupleId));
    }
  }

  return ({
    required String coupleId,
    required int lastReadMessageId,
    required DateTime lastReadAt,
  }) {
    final previous = queueTailByCouple[coupleId];
    final waitForPrevious = previous == null
        ? Future<void>.value()
        : previous.then<void>((_) {}, onError: (_, __) {});
    final operation = waitForPrevious.then<void>(
      (_) => perform(
        coupleId: coupleId,
        lastReadMessageId: lastReadMessageId,
        lastReadAt: lastReadAt,
      ),
    );
    late final Future<void> safeTail;
    safeTail = operation.then<void>((_) {}, onError: (_, __) {}).whenComplete(
      () {
        if (identical(queueTailByCouple[coupleId], safeTail)) {
          queueTailByCouple.remove(coupleId);
        }
      },
    );
    queueTailByCouple[coupleId] = safeTail;
    return operation;
  };
});

final chatUnreadCountProvider =
    StreamProvider.family<int, String>((ref, coupleId) {
  final myUserId = ref.watch(chatCurrentUserIdProvider);
  if (myUserId == null) {
    return Stream<int>.value(0);
  }

  final markerAsync = ref.watch(chatReadMarkerProvider(coupleId));
  final lastReadMessageId = markerAsync.valueOrNull?.lastReadMessageId ?? 0;
  return (() async* {
    try {
      yield* ref.read(chatRepositoryProvider).watchUnreadCount(
            coupleId: coupleId,
            myUserId: myUserId,
            lastReadMessageId: lastReadMessageId,
          );
    } catch (_) {
      yield 0;
    }
  })();
});

final chatLatestMessageAtProvider =
    StreamProvider.family<DateTime?, String>((ref, coupleId) {
  final messagesStream = ref.watch(chatWatchMessagesProvider)(coupleId);
  return messagesStream.map((messages) {
    if (messages.isEmpty) return null;
    return messages.last.createdAt;
  });
});

final chatPartnerOnlineProvider =
    StreamProvider.family<bool, String>((ref, coupleId) async* {
  try {
    yield* ref.read(chatRepositoryProvider).watchPartnerOnline(coupleId);
  } catch (_) {
    yield false;
  }
});

final chatConversationPreviewProvider =
    StreamProvider.family<ChatConversationPreview?, String>((ref, coupleId) {
  final messagesStream = ref.watch(chatWatchMessagesProvider)(coupleId);
  return messagesStream.map((messages) {
    if (messages.isEmpty) return null;

    final latest = messages.last;
    final body = latest.body?.trim();
    final previewText = body != null && body.isNotEmpty
        ? body
        : latest.hasImage
            ? '사진을 보냈어요'
            : '새 메시지가 있어요';

    return ChatConversationPreview(
      text: previewText,
      createdAt: latest.createdAt,
    );
  });
});

final chatLatestImageAtProvider =
    StreamProvider.family<DateTime?, String>((ref, coupleId) {
  final messagesStream = ref.watch(chatWatchMessagesProvider)(coupleId);
  return messagesStream.map((messages) {
    DateTime? latest;
    for (final message in messages) {
      if (!message.hasImage) continue;
      final createdAt = message.createdAt;
      if (latest == null || createdAt.isAfter(latest)) {
        latest = createdAt;
      }
    }
    return latest;
  });
});
