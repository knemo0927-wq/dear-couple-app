import 'dart:async';

import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_format.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_image_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    required this.coupleId,
    super.key,
  });

  final String coupleId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _sending = false;
  bool _sendingImage = false;
  final List<_PendingImageUpload> _pendingImages = <_PendingImageUpload>[];
  int _nextPendingImageId = 0;
  final List<_OptimisticTextMessage> _optimisticTexts =
      <_OptimisticTextMessage>[];
  ChatMessage? _replyingTo;
  int _nextOptimisticId = -1;
  final List<ChatMessage> _olderMessages = <ChatMessage>[];
  bool _loadingOlder = false;
  bool _hasMoreOlder = true;
  String? _error;
  Future<void> Function()? _retryAction;
  bool _retryIsImage = false;
  int? _lastMarkedReadMessageId;
  ChatMessage? _pendingReadMessage;
  bool _markReadInFlight = false;
  Timer? _readRetryTimer;
  int _readRetryAttempt = 0;
  int? _lastObservedMessageId;
  bool _didInitialAutoScroll = false;
  bool _keyboardWasVisible = false;
  StreamSubscription<int>? _reactionSubscription;
  int _streamRevision = 0;

  ChatWatchMessages get _watchMessages => ref.read(chatWatchMessagesProvider);
  ChatSendReplyTextAction get _sendTextAction =>
      ref.read(chatSendReplyTextProvider);
  ChatUploadImageAction get _uploadImageAction =>
      ref.read(chatUploadImageProvider);
  ChatFetchMessagesPage get _fetchMessagesPage =>
      ref.read(chatFetchMessagesPageProvider);
  ChatToggleReactionAction get _toggleReactionAction =>
      ref.read(chatToggleReactionProvider);
  ChatPickImageAction get _pickImageAction => ref.read(chatPickImageProvider);
  ChatPickImagesAction get _pickImagesAction =>
      ref.read(chatPickImagesProvider);
  ChatMarkReadAction get _markReadAction => ref.read(chatMarkReadProvider);

  PickedChatImage? get _pendingImage =>
      _pendingImages.isEmpty ? null : _pendingImages.first.image;

  set _pendingImage(PickedChatImage? image) {
    _pendingImages.clear();
    if (image != null) _pendingImages.add(_createPendingImage(image));
  }

  _PendingImageUpload _createPendingImage(PickedChatImage image) {
    final sequence = _nextPendingImageId++;
    return _PendingImageUpload(
      image: image,
      fingerprint: _imageFingerprint(image),
      idempotencyKey:
          '${DateTime.now().microsecondsSinceEpoch}_${sequence.toRadixString(36)}',
    );
  }

  String _imageFingerprint(PickedChatImage image) {
    var hash = 0x811c9dc5;
    for (final byte in image.bytes) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return '${image.extension}:${image.bytes.lengthInBytes}:${hash.toRadixString(16)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
    _reactionSubscription = ref
        .read(chatWatchReactionMessageIdsProvider)(widget.coupleId)
        .listen(_refreshOlderMessageReaction);
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) {
        _scheduleScrollToBottom(animated: true);
      }
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final isKeyboardVisible =
        (view.viewInsets.bottom / view.devicePixelRatio) > 0;
    if (isKeyboardVisible && !_keyboardWasVisible) {
      _scrollToBottomForKeyboardOpen();
    }
    _keyboardWasVisible = isKeyboardVisible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || _pendingReadMessage == null) {
      return;
    }
    _readRetryTimer?.cancel();
    _readRetryTimer = null;
    unawaited(_flushPendingReadMarker());
  }

  void _scrollToBottomForKeyboardOpen() {
    _scheduleScrollToBottom(animated: true);
    Future<void>.delayed(
      const Duration(milliseconds: 120),
      () {
        if (!mounted) return;
        _scheduleScrollToBottom(animated: false);
      },
    );
    Future<void>.delayed(
      const Duration(milliseconds: 280),
      () {
        if (!mounted) return;
        _scheduleScrollToBottom(animated: false);
      },
    );
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _refreshOlderMessageReaction(int messageId) async {
    if (!_olderMessages.any((message) => message.id == messageId)) return;
    try {
      final refreshed = await ref.read(chatFetchMessageByIdProvider)(
        coupleId: widget.coupleId,
        messageId: messageId,
      );
      if (!mounted || refreshed == null) return;
      setState(() {
        final index = _olderMessages.indexWhere(
          (message) => message.id == messageId,
        );
        if (index >= 0) _olderMessages[index] = refreshed;
      });
    } catch (_) {
      // The existing reaction state remains usable until the next event.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reactionSubscription?.cancel();
    _readRetryTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<bool> _runSend(
    Future<void> Function() action, {
    required bool clearTextOnSuccess,
  }) async {
    if (_sending) return false;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await action();
      if (!mounted) return false;
      if (clearTextOnSuccess) {
        _messageController.clear();
      }
      setState(() {
        _retryAction = null;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _error = toFriendlyErrorMessage(e);
        _retryAction = action;
      });
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (_sending || text.isEmpty) return;
    final replyingTo = _replyingTo;
    final optimistic = _OptimisticTextMessage(
      localId: _nextOptimisticId--,
      text: text,
      sentAt: DateTime.now(),
      replyPreview: replyingTo == null
          ? null
          : (replyingTo.hasText ? replyingTo.body!.trim() : '사진'),
    );
    setState(() {
      _sending = true;
      _error = null;
      _retryAction = null;
      _optimisticTexts.add(optimistic);
      _messageController.clear();
      _replyingTo = null;
    });
    _scheduleScrollToBottom(animated: true);

    Future<void> send() async {
      await _sendTextAction(
        coupleId: widget.coupleId,
        text: text,
        replyToMessageId: replyingTo?.id,
      );
      if (!mounted) return;
      setState(() => _optimisticTexts.remove(optimistic));
    }

    try {
      await send();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        optimistic.status = _OptimisticSendStatus.failed;
        _error = toFriendlyErrorMessage(error);
        _retryIsImage = false;
        _retryAction = () async {
          if (mounted) {
            setState(() => optimistic.status = _OptimisticSendStatus.sending);
          }
          try {
            await send();
          } catch (_) {
            if (mounted) {
              setState(() => optimistic.status = _OptimisticSendStatus.failed);
            }
            rethrow;
          }
        };
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleMessageReaction(int messageId) async {
    try {
      await _toggleReactionAction(messageId: messageId);
      if (!mounted) return;
      setState(() {
        _error = null;
        _retryAction = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = toFriendlyErrorMessage(e);
        _retryAction = () => _toggleReactionAction(messageId: messageId);
      });
    }
  }

  Future<void> _showMessageActions(
    ChatMessage message, {
    required bool isMine,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('답장'),
              onTap: () => Navigator.pop(sheetContext, 'reply'),
            ),
            if (message.hasText)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('복사'),
                onTap: () => Navigator.pop(sheetContext, 'copy'),
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('삭제'),
                textColor: Theme.of(sheetContext).colorScheme.error,
                iconColor: Theme.of(sheetContext).colorScheme.error,
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'copy' && message.body != null) {
      await Clipboard.setData(ClipboardData(text: message.body!));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메시지를 복사했어요.')),
      );
      return;
    }
    if (action == 'reply') {
      setState(() => _replyingTo = message);
      _inputFocusNode.requestFocus();
      return;
    }
    if (action == 'delete') {
      try {
        await ref.read(chatDeleteMessageProvider)(message.id);
        if (!mounted) return;
        setState(() {
          _olderMessages.removeWhere((item) => item.id == message.id);
          _lastVisibleMessages = _lastVisibleMessages
              .where((item) => item.id != message.id)
              .toList(growable: false);
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _error = toFriendlyErrorMessage(error);
          _retryAction = () => ref.read(chatDeleteMessageProvider)(message.id);
        });
      }
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels < 180) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_hasMoreOlder) return;
    final oldestId = _olderMessages.isNotEmpty
        ? _olderMessages.first.id
        : _lastVisibleMessages.isNotEmpty
            ? _lastVisibleMessages.first.id
            : null;
    if (oldestId == null) return;

    final previousExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    setState(() => _loadingOlder = true);
    try {
      final page = await _fetchMessagesPage(
        coupleId: widget.coupleId,
        beforeMessageId: oldestId,
        limit: ChatRepository.initialPageSize,
      );
      if (!mounted) return;
      final existingIds = <int>{
        ..._olderMessages.map((message) => message.id),
        ..._lastVisibleMessages.map((message) => message.id),
      };
      setState(() {
        _olderMessages.insertAll(
          0,
          page.messages.where((message) => !existingIds.contains(message.id)),
        );
        _olderMessages.sort((a, b) {
          final date = a.createdAt.compareTo(b.createdAt);
          return date != 0 ? date : a.id.compareTo(b.id);
        });
        _hasMoreOlder = page.hasMore;
        _error = null;
        _retryAction = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final addedExtent =
            _scrollController.position.maxScrollExtent - previousExtent;
        if (addedExtent > 0) {
          _scrollController.jumpTo(
            (_scrollController.position.pixels + addedExtent)
                .clamp(
                  0,
                  _scrollController.position.maxScrollExtent,
                )
                .toDouble(),
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = toFriendlyErrorMessage(error);
        _retryAction = _loadOlderMessages;
      });
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  List<ChatMessage> _lastVisibleMessages = const <ChatMessage>[];

  Future<void> _pickImage() async {
    if (_sending) return;

    final picked = await _pickImageAction();
    if (picked == null) return;

    final normalizedExtension = normalizeImageExtension(picked.extension);
    if (!isSupportedImageExtension(normalizedExtension)) {
      if (!mounted) return;
      setState(() {
        _pendingImage = null;
        _error = 'JPG, PNG, WEBP 형식 이미지만 전송할 수 있어요.';
        _retryAction = null;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _pendingImage = PickedChatImage(
        bytes: picked.bytes,
        extension: normalizedExtension,
      );
      _error = null;
      _retryAction = null;
    });
  }

  Future<void> _pickMultipleImages({bool append = false}) async {
    if (_sending) return;
    final picked = await _pickImagesAction();
    if (picked.isEmpty || !mounted) return;

    final normalized = <PickedChatImage>[];
    for (final image in picked.take(10)) {
      final extension = normalizeImageExtension(image.extension);
      if (!isSupportedImageExtension(extension)) {
        setState(() {
          _error = 'JPG, PNG, WEBP 형식 이미지만 전송할 수 있어요.';
          _retryAction = null;
        });
        return;
      }
      normalized.add(
        PickedChatImage(bytes: image.bytes, extension: extension),
      );
    }

    var skippedDuplicates = 0;
    setState(() {
      if (!append) _pendingImages.clear();
      final fingerprints =
          _pendingImages.map((pending) => pending.fingerprint).toSet();
      for (final image in normalized) {
        if (_pendingImages.length >= 10) break;
        final pending = _createPendingImage(image);
        if (fingerprints.add(pending.fingerprint)) {
          _pendingImages.add(pending);
        } else {
          skippedDuplicates += 1;
        }
      }
      _error = null;
      _retryAction = null;
    });
    if (skippedDuplicates > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 선택한 사진은 한 번만 추가했어요.')),
      );
    }
  }

  ChatMessage? _latestPartnerMessage(
      List<ChatMessage> messages, String myUserId) {
    ChatMessage? latest;
    for (final message in messages) {
      if (message.senderId == myUserId) continue;
      if (latest == null || message.id > latest.id) {
        latest = message;
      }
    }
    return latest;
  }

  void _markConversationRead(ChatMessage message) {
    if (_lastMarkedReadMessageId != null &&
        message.id <= _lastMarkedReadMessageId!) {
      return;
    }

    final pendingId = _pendingReadMessage?.id;
    final hasNewerMessage = pendingId == null || message.id > pendingId;
    if (hasNewerMessage) {
      _pendingReadMessage = message;
    }
    if (_markReadInFlight) return;

    if (_readRetryTimer?.isActive ?? false) {
      if (!hasNewerMessage) return;
      _readRetryTimer?.cancel();
      _readRetryTimer = null;
    }
    unawaited(_flushPendingReadMarker());
  }

  Future<void> _flushPendingReadMarker() async {
    if (!mounted || _markReadInFlight) return;
    final target = _pendingReadMessage;
    if (target == null) return;
    if (_lastMarkedReadMessageId != null &&
        target.id <= _lastMarkedReadMessageId!) {
      _pendingReadMessage = null;
      return;
    }

    _markReadInFlight = true;
    var shouldRetryImmediately = false;
    try {
      await _markReadAction(
        coupleId: widget.coupleId,
        lastReadMessageId: target.id,
        lastReadAt: target.createdAt,
      );
      if (!mounted) return;
      if (_lastMarkedReadMessageId == null ||
          target.id > _lastMarkedReadMessageId!) {
        _lastMarkedReadMessageId = target.id;
      }
      if ((_pendingReadMessage?.id ?? 0) <= target.id) {
        _pendingReadMessage = null;
      }
      _readRetryAttempt = 0;
      _readRetryTimer?.cancel();
      _readRetryTimer = null;
    } catch (_) {
      if (!mounted) return;
      shouldRetryImmediately = (_pendingReadMessage?.id ?? 0) > target.id;
      if (!shouldRetryImmediately) _scheduleReadMarkerRetry();
    } finally {
      _markReadInFlight = false;
    }

    if (mounted &&
        _pendingReadMessage != null &&
        (shouldRetryImmediately || !(_readRetryTimer?.isActive ?? false))) {
      unawaited(_flushPendingReadMarker());
    }
  }

  void _scheduleReadMarkerRetry() {
    if (_readRetryTimer?.isActive ?? false) return;
    const delays = <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ];
    final index = _readRetryAttempt.clamp(0, delays.length - 1);
    _readRetryAttempt += 1;
    _readRetryTimer = Timer(delays[index], () {
      _readRetryTimer = null;
      if (!mounted) return;
      unawaited(_flushPendingReadMarker());
    });
  }

  void _scheduleScrollToBottom({required bool animated}) {
    _scrollToBottomInternal(animated: animated, retries: animated ? 1 : 6);
  }

  void _scrollToBottomInternal({
    required bool animated,
    required int retries,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (!_scrollController.hasClients) {
        if (retries > 1) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          if (!mounted) return;
          _scrollToBottomInternal(animated: animated, retries: retries - 1);
        }
        return;
      }

      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        await _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }

      if (!animated && retries > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        if (!mounted) return;
        _scrollToBottomInternal(animated: false, retries: retries - 1);
      }
    });
  }

  Future<void> _sendPendingImages({Set<String>? onlyKeys}) async {
    if (_sendingImage) return;
    final pending = _pendingImages.where((item) {
      if (onlyKeys != null && !onlyKeys.contains(item.idempotencyKey)) {
        return false;
      }
      return item.status == _PendingImageStatus.queued ||
          item.status == _PendingImageStatus.failed;
    }).toList(growable: false);
    if (pending.isEmpty) return;
    if (pending.any(
      (item) =>
          !isSupportedImageExtension(item.image.extension) ||
          isImageTooLarge(item.image.bytes.lengthInBytes),
    )) {
      setState(() {
        _error = '지원하지 않는 형식이거나 8MB를 넘는 사진이 있어요.';
        _retryAction = null;
      });
      return;
    }

    setState(() {
      _sending = true;
      _sendingImage = true;
      _error = null;
      _retryAction = null;
      _retryIsImage = false;
    });
    try {
      for (final item in pending) {
        if (!mounted || !_pendingImages.contains(item)) continue;
        if (item.cancelRequested) {
          setState(() => _pendingImages.remove(item));
          continue;
        }
        setState(() {
          item.status = _PendingImageStatus.uploading;
          item.progress = 0.05;
        });
        try {
          final outcome = await _uploadImageAction(
            coupleId: widget.coupleId,
            bytes: item.image.bytes,
            extension: item.image.extension,
            idempotencyKey: item.idempotencyKey,
            isCancelled: () => item.cancelRequested,
            onProgress: (progress) {
              if (!mounted || !_pendingImages.contains(item)) return;
              setState(() => item.progress = progress.clamp(0, 1));
            },
          );
          if (!mounted) return;
          setState(() {
            _pendingImages.remove(item);
            if (outcome == ChatImageSendOutcome.cancelled) {
              _error = null;
            }
          });
        } catch (error) {
          if (!mounted) return;
          setState(() {
            item.status = _PendingImageStatus.failed;
            item.progress = 0;
            _error = toFriendlyErrorMessage(error);
            _retryIsImage = true;
            _retryAction = () => _sendPendingImages(
                  onlyKeys: {item.idempotencyKey},
                );
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingImage = false;
        });
      }
    }
  }

  void _removeOrCancelPending(_PendingImageUpload item) {
    setState(() {
      if (item.status == _PendingImageStatus.uploading) {
        item.cancelRequested = true;
        item.status = _PendingImageStatus.cancelling;
      } else {
        _pendingImages.remove(item);
      }
    });
  }

  void _cancelAllPending() {
    setState(() {
      for (final item in _pendingImages) {
        if (item.status == _PendingImageStatus.uploading ||
            item.status == _PendingImageStatus.cancelling) {
          item.cancelRequested = true;
          item.status = _PendingImageStatus.cancelling;
        }
      }
      _pendingImages.removeWhere(
        (item) => item.status != _PendingImageStatus.cancelling,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.watch(chatCurrentUserIdProvider);
    final avatarUrlMapAsync =
        ref.watch(coupleAvatarUrlMapProvider(widget.coupleId));
    final partnerLastReadMessageId = ref
        .watch(chatPartnerReadMarkerProvider(widget.coupleId))
        .valueOrNull
        ?.lastReadMessageId;
    final canSendText = !_sending && _messageController.text.trim().isNotEmpty;
    final pendingBytes = _pendingImages.fold<int>(
      0,
      (total, item) => total + item.image.bytes.lengthInBytes,
    );
    final hasOversizedPending = _pendingImages.any(
      (item) => isImageTooLarge(item.image.bytes.lengthInBytes),
    );
    final hasLargePending = _pendingImages.any(
      (item) => isImageSizeWarning(item.image.bytes.lengthInBytes),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismissKeyboard,
      child: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              key: ValueKey<int>(_streamRevision),
              stream: _watchMessages(widget.coupleId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: DearCard(
                      margin: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const DearIconBubble(
                            icon: Icons.cloud_off_rounded,
                            size: 58,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            toFriendlyErrorMessage(snapshot.error!),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () =>
                                setState(() => _streamRevision += 1),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const _ChatLoadingSkeleton();
                }

                final liveMessages = snapshot.data!;
                final messagesById = <int, ChatMessage>{
                  for (final message in _olderMessages) message.id: message,
                  for (final message in liveMessages) message.id: message,
                };
                final messages = messagesById.values.toList()
                  ..sort((a, b) {
                    final date = a.createdAt.compareTo(b.createdAt);
                    return date != 0 ? date : a.id.compareTo(b.id);
                  });
                _lastVisibleMessages = messages;
                if (_olderMessages.isEmpty &&
                    liveMessages.length < ChatRepository.initialPageSize) {
                  _hasMoreOlder = false;
                }
                if (messages.isEmpty && _optimisticTexts.isEmpty) {
                  _lastObservedMessageId = null;
                  _didInitialAutoScroll = false;
                  return Center(
                    child: DearCard(
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      padding: const EdgeInsets.all(24),
                      shadowOpacity: 0.55,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const DearIconBubble(
                            icon: Icons.chat_bubble_rounded,
                            size: 58,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '첫 대화를 시작해요',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: DearColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '오늘 남기고 싶은 말을 편하게 보내보세요.',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: DearColors.muted,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (messages.isNotEmpty) {
                  final latestMessageId = messages.last.id;
                  if (_lastObservedMessageId != latestMessageId) {
                    final animated = _didInitialAutoScroll;
                    _lastObservedMessageId = latestMessageId;
                    _scheduleScrollToBottom(animated: animated);
                    _didInitialAutoScroll = true;
                  }
                }

                final avatarUrlByUserId =
                    avatarUrlMapAsync.valueOrNull ?? const <String, String>{};
                final nicknameByUserId = ref
                        .watch(coupleNicknameMapProvider(widget.coupleId))
                        .valueOrNull ??
                    const <String, String>{};

                if (myUserId != null) {
                  final latestPartnerMessage =
                      _latestPartnerMessage(messages, myUserId);
                  if (latestPartnerMessage != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _markConversationRead(latestPartnerMessage);
                    });
                  }
                }

                final listBottomPadding = _pendingImage != null
                    ? 98.0
                    : (_error != null || _sendingImage ? 58.0 : 18.0);
                final entries = _groupChatImageMessages(messages);

                return ListView.builder(
                  controller: _scrollController,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(16, 18, 16, listBottomPadding),
                  itemCount: entries.length + _optimisticTexts.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _OlderMessagesHeader(
                        loading: _loadingOlder,
                        hasMore: _hasMoreOlder,
                        onLoad: _loadOlderMessages,
                      );
                    }
                    final entryIndex = index - 1;
                    if (entryIndex >= entries.length) {
                      final optimisticIndex = entryIndex - entries.length;
                      return _OptimisticTextBubble(
                        message: _optimisticTexts[optimisticIndex],
                      );
                    }
                    final entry = entries[entryIndex];
                    final message = entry.first;
                    final lastMessage = entry.last;
                    final previous =
                        entryIndex > 0 ? entries[entryIndex - 1].last : null;
                    final next = entryIndex + 1 < entries.length
                        ? entries[entryIndex + 1].first
                        : null;
                    final isMine = message.senderId == myUserId;
                    final showDateChip =
                        needsDateHeader(message.createdAt, previous?.createdAt);
                    final showSenderAvatar = !isMine &&
                        (previous == null ||
                            previous.senderId != message.senderId ||
                            showDateChip);
                    final showMessageTime = next == null ||
                        next.senderId != lastMessage.senderId ||
                        !isSameMinute(lastMessage.createdAt, next.createdAt);
                    final resolvedNickname =
                        nicknameByUserId[message.senderId]?.trim() ?? '';
                    final senderNickname = resolvedNickname.isNotEmpty
                        ? resolvedNickname
                        : '사용자 ${message.senderId.substring(0, 6)}';

                    return Column(
                      children: [
                        if (showDateChip)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.84),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: DearColors.line),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    chatDateLabel(message.createdAt),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: DearColors.secondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: isMine
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Flexible(
                                      child: _ChatBubbleContent(
                                        message: message,
                                        imageMessages: entry.messages,
                                        replyMessage:
                                            message.replyToMessageId == null
                                                ? null
                                                : messagesById[
                                                    message.replyToMessageId],
                                        isMine: true,
                                        isReadByPartner:
                                            partnerLastReadMessageId != null &&
                                                lastMessage.id <=
                                                    partnerLastReadMessageId,
                                        showMessageTime: showMessageTime,
                                        onLongPress: () => _showMessageActions(
                                          lastMessage,
                                          isMine: true,
                                        ),
                                        onToggleHeart: () =>
                                            _toggleMessageReaction(
                                          lastMessage.id,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : _OtherSenderMessageCluster(
                                  showHeader: showSenderAvatar,
                                  avatarHeroTag: 'chat-avatar-${message.id}',
                                  avatarUrl:
                                      avatarUrlByUserId[message.senderId],
                                  nickname: senderNickname,
                                  onTapAvatar: (avatarUrl, heroTag) {
                                    if (avatarUrl == null ||
                                        avatarUrl.isEmpty) {
                                      return;
                                    }
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChatImageViewPage(
                                          imageUrl: avatarUrl,
                                          heroTag: heroTag,
                                        ),
                                      ),
                                    );
                                  },
                                  child: _ChatBubbleContent(
                                    message: message,
                                    imageMessages: entry.messages,
                                    replyMessage:
                                        message.replyToMessageId == null
                                            ? null
                                            : messagesById[
                                                message.replyToMessageId],
                                    isMine: false,
                                    isReadByPartner: false,
                                    showMessageTime: showMessageTime,
                                    onLongPress: () => _showMessageActions(
                                      lastMessage,
                                      isMine: false,
                                    ),
                                    onToggleHeart: () =>
                                        _toggleMessageReaction(lastMessage.id),
                                  ),
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  if (_retryAction != null)
                    OutlinedButton(
                      onPressed: _sending
                          ? null
                          : () async {
                              final retry = _retryAction;
                              if (retry == null) return;
                              if (_retryIsImage) {
                                await retry();
                                return;
                              }
                              await _runSend(
                                retry,
                                clearTextOnSuccess: false,
                              );
                            },
                      child: const Text('다시 시도'),
                    ),
                ],
              ),
            ),
          if (_replyingTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: DearColors.blush,
                  borderRadius: BorderRadius.circular(DearRadii.medium),
                  border: Border.all(color: DearColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.reply_rounded,
                      size: 18,
                      color: DearColors.coralText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '답장하기',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: DearColors.coralText,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          Text(
                            _replyingTo!.hasText
                                ? _replyingTo!.body!.trim()
                                : '사진',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '답장 취소',
                      onPressed: () => setState(() => _replyingTo = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          if (_pendingImage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: DearColors.line),
                  boxShadow: dearSoftShadow(0.35),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pendingImages.length == 1
                            ? '이미지 미리보기 (${_pendingImage!.extension.toUpperCase()})'
                            : '선택한 사진 ${_pendingImages.length}장',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: DearColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _pendingImages.length == 1
                            ? '${_pendingImage!.extension.toUpperCase()} · ${formatImageSizeLabel(pendingBytes)}'
                            : '합계 ${formatImageSizeLabel(pendingBytes)} · 최대 10장',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: DearColors.secondary,
                            ),
                      ),
                      if (hasLargePending)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            hasOversizedPending
                                ? '8MB 초과 이미지는 전송할 수 없어요.'
                                : '용량이 커서 전송이 느릴 수 있어요.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _pendingImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final pending = _pendingImages[index];
                            final image = pending.image;
                            return Stack(
                              children: [
                                SizedBox(
                                  key: index == 0
                                      ? const Key('pending-image-thumbnail')
                                      : Key('pending-image-thumbnail-$index'),
                                  width: 92,
                                  height: 92,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.memory(
                                      image.bytes,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          color: DearColors.blush,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: DearColors.disabled,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: -5,
                                  top: -5,
                                  child: Tooltip(
                                    message: '${index + 1}번째 사진 제거',
                                    child: Semantics(
                                      button: true,
                                      label: '${index + 1}번째 사진 제거',
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Center(
                                          child: Material(
                                            color: DearColors.ink.withValues(
                                              alpha: 0.72,
                                            ),
                                            shape: const CircleBorder(),
                                            child: InkWell(
                                              customBorder:
                                                  const CircleBorder(),
                                              onTap: () =>
                                                  _removeOrCancelPending(
                                                      pending),
                                              child: const SizedBox(
                                                width: 28,
                                                height: 28,
                                                child: Icon(
                                                  Icons.close_rounded,
                                                  size: 17,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (pending.status ==
                                        _PendingImageStatus.uploading ||
                                    pending.status ==
                                        _PendingImageStatus.cancelling)
                                  Positioned(
                                    left: 5,
                                    right: 5,
                                    bottom: 5,
                                    child: Semantics(
                                      label: pending.status ==
                                              _PendingImageStatus.cancelling
                                          ? '업로드 취소 중'
                                          : '업로드 ${(pending.progress * 100).round()}퍼센트',
                                      child: LinearProgressIndicator(
                                        value: pending.progress,
                                        minHeight: 5,
                                        backgroundColor: Colors.white70,
                                      ),
                                    ),
                                  ),
                                if (pending.status ==
                                    _PendingImageStatus.failed)
                                  Positioned(
                                    left: 3,
                                    bottom: 3,
                                    child: Material(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                      shape: const CircleBorder(),
                                      child: IconButton(
                                        key: ValueKey<String>(
                                          'retry-image-${pending.idempotencyKey}',
                                        ),
                                        tooltip: '${index + 1}번째 사진 다시 시도',
                                        onPressed: _sendingImage
                                            ? null
                                            : () => _sendPendingImages(
                                                  onlyKeys: {
                                                    pending.idempotencyKey,
                                                  },
                                                ),
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: _sending
                                ? null
                                : _pendingImages.length == 1
                                    ? _pickImage
                                    : () => _pickMultipleImages(append: true),
                            child: Text(
                              _pendingImages.length == 1 ? '다른 이미지' : '사진 추가',
                            ),
                          ),
                          TextButton(
                            onPressed: _cancelAllPending,
                            child: const Text('취소'),
                          ),
                          FilledButton(
                            onPressed: _sendingImage || hasOversizedPending
                                ? null
                                : _sendPendingImages,
                            child: Text(
                              _pendingImages.length == 1
                                  ? '이미지 전송'
                                  : '${_pendingImages.length}장 전송',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_sendingImage)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '이미지 업로드 중...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DearColors.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: DearColors.line),
                boxShadow: dearSoftShadow(0.45),
              ),
              child: Row(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: DearColors.coralSoft,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      tooltip: '사진 한 장 선택',
                      onPressed: _sending ? null : _pickImage,
                      icon: const Icon(Icons.image_outlined),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '사진 여러 장 선택',
                    onPressed: _sending ? null : () => _pickMultipleImages(),
                    icon: const Icon(Icons.collections_outlined),
                    color: DearColors.coralText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _inputFocusNode,
                      onChanged: (_) => setState(() {}),
                      minLines: 1,
                      maxLines: 4,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: DearColors.ink,
                          ),
                      decoration: const InputDecoration(
                        hintText: '메시지 입력...',
                        hintStyle: TextStyle(color: DearColors.disabled),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: DearColors.coralText,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFF3E7EC),
                        disabledForegroundColor: DearColors.disabled,
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: canSendText ? _sendText : null,
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PendingImageStatus { queued, uploading, cancelling, failed }

class _PendingImageUpload {
  _PendingImageUpload({
    required this.image,
    required this.fingerprint,
    required this.idempotencyKey,
  });

  final PickedChatImage image;
  final String fingerprint;
  final String idempotencyKey;
  _PendingImageStatus status = _PendingImageStatus.queued;
  double progress = 0;
  bool cancelRequested = false;
}

List<_ChatMessageEntry> _groupChatImageMessages(List<ChatMessage> messages) {
  final entries = <_ChatMessageEntry>[];
  for (final message in messages) {
    final canJoinPrevious = message.hasImage &&
        !message.hasText &&
        entries.isNotEmpty &&
        entries.last.isImageGroup &&
        entries.last.messages.length < 10 &&
        entries.last.last.senderId == message.senderId &&
        isSameMinute(entries.last.last.createdAt, message.createdAt);
    if (canJoinPrevious) {
      entries.last.messages.add(message);
    } else {
      entries.add(_ChatMessageEntry(<ChatMessage>[message]));
    }
  }
  return entries;
}

class _ChatMessageEntry {
  _ChatMessageEntry(this.messages);

  final List<ChatMessage> messages;
  ChatMessage get first => messages.first;
  ChatMessage get last => messages.last;
  bool get isImageGroup => first.hasImage && !first.hasText;
}

enum _OptimisticSendStatus { sending, failed }

class _OptimisticTextMessage {
  _OptimisticTextMessage({
    required this.localId,
    required this.text,
    required this.sentAt,
    this.replyPreview,
  }) : status = _OptimisticSendStatus.sending;

  final int localId;
  final String text;
  final DateTime sentAt;
  final String? replyPreview;
  _OptimisticSendStatus status;
}

class _OptimisticTextBubble extends StatelessWidget {
  const _OptimisticTextBubble({required this.message});

  final _OptimisticTextMessage message;

  @override
  Widget build(BuildContext context) {
    final failed = message.status == _OptimisticSendStatus.failed;
    return Semantics(
      label: failed ? '전송 실패한 내 메시지' : '전송 중인 내 메시지',
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                key: ValueKey<int>(message.localId),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: DearColors.coralSoft,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(6),
                  ),
                  border: Border.all(
                    color: failed
                        ? Theme.of(context).colorScheme.error
                        : DearColors.line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.replyPreview != null) ...[
                      _ReplyPreview(text: message.replyPreview!),
                      const SizedBox(height: 7),
                    ],
                    Text(message.text),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    failed ? Icons.error_outline_rounded : Icons.schedule,
                    size: 13,
                    color: failed
                        ? Theme.of(context).colorScheme.error
                        : DearColors.secondary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${failed ? '전송 실패' : '전송 중'} · ${chatTimeLabel(message.sentAt)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: failed
                              ? Theme.of(context).colorScheme.error
                              : DearColors.secondary,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OlderMessagesHeader extends StatelessWidget {
  const _OlderMessagesHeader({
    required this.loading,
    required this.hasMore,
    required this.onLoad,
  });

  final bool loading;
  final bool hasMore;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!hasMore) return const SizedBox(height: 4);
    return Center(
      child: TextButton.icon(
        onPressed: onLoad,
        icon: const Icon(Icons.history_rounded, size: 18),
        label: const Text('이전 메시지 불러오기'),
      ),
    );
  }
}

class _ChatLoadingSkeleton extends StatelessWidget {
  const _ChatLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '채팅 불러오는 중',
      child: ListView.separated(
        key: const Key('chat-loading-skeleton'),
        padding: const EdgeInsets.all(18),
        itemCount: 7,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final mine = index.isOdd;
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: MediaQuery.sizeOf(context).width * (mine ? .52 : .64),
              height: index % 3 == 0 ? 72 : 44,
              decoration: BoxDecoration(
                color: mine ? DearColors.coralSoft : Colors.white,
                borderRadius: BorderRadius.circular(DearRadii.large),
                border: Border.all(color: DearColors.line),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(DearRadii.small),
        border: const Border(
          left: BorderSide(color: DearColors.coralText, width: 3),
        ),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: DearColors.secondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ChatBubbleContent extends StatelessWidget {
  const _ChatBubbleContent({
    required this.message,
    required this.imageMessages,
    required this.replyMessage,
    required this.isMine,
    required this.isReadByPartner,
    required this.showMessageTime,
    required this.onLongPress,
    required this.onToggleHeart,
  });

  final ChatMessage message;
  final List<ChatMessage> imageMessages;
  final ChatMessage? replyMessage;
  final bool isMine;
  final bool isReadByPartner;
  final bool showMessageTime;
  final VoidCallback onLongPress;
  final VoidCallback onToggleHeart;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.hasText)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: isMine
                      ? const LinearGradient(
                          colors: [DearColors.blushDeep, DearColors.coralSoft],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isMine ? null : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isMine ? 20 : 6),
                    bottomRight: Radius.circular(isMine ? 6 : 20),
                  ),
                  border: Border.all(
                    color: DearColors.line,
                    width: 0.7,
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                      color: DearColors.shadow.withValues(alpha: 0.06),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.replyToMessageId != null) ...[
                        _ReplyPreview(
                          text: replyMessage == null
                              ? '답장한 메시지'
                              : (replyMessage!.hasText
                                  ? replyMessage!.body!.trim()
                                  : '사진'),
                        ),
                        const SizedBox(height: 7),
                      ],
                      Text(
                        message.body!,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: DearColors.ink,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (imageMessages.length > 1)
            Padding(
              padding: EdgeInsets.only(top: message.hasText ? 6 : 0),
              child: _MessageImageMosaic(
                messages: imageMessages,
                isMine: isMine,
                showTimeLabel: showMessageTime,
                maxWidth: MediaQuery.sizeOf(context).width * 0.68,
              ),
            )
          else if (message.hasImage)
            Padding(
              padding: EdgeInsets.only(
                top: message.hasText ? 6 : 0,
              ),
              child: _MessageImage(
                imagePath: message.imagePath!,
                messageId: message.id,
                sentAt: message.createdAt,
                isMine: isMine,
                showTimeLabel: showMessageTime,
                maxWidth: MediaQuery.sizeOf(context).width * 0.62,
              ),
            ),
          const SizedBox(height: 4),
          _MessageMetaRow(
            isMine: isMine,
            deliveryLabel: isMine ? (isReadByPartner ? '읽음' : '전송됨') : null,
            showTimeLabel: !message.hasImage && showMessageTime,
            timeLabel: chatTimeLabel(imageMessages.last.createdAt),
            heartCount: imageMessages.last.heartCount,
            isHeartedByMe: imageMessages.last.isHeartedByMe,
            onToggleHeart: onToggleHeart,
          ),
        ],
      ),
    );
  }
}

class _OtherSenderMessageCluster extends StatelessWidget {
  const _OtherSenderMessageCluster({
    required this.showHeader,
    required this.avatarHeroTag,
    required this.avatarUrl,
    required this.nickname,
    required this.onTapAvatar,
    required this.child,
  });

  final bool showHeader;
  final String avatarHeroTag;
  final String? avatarUrl;
  final String nickname;
  final void Function(String?, String) onTapAvatar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const bubbleIndent = 47.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SenderAvatar(
                imageUrl: avatarUrl,
                heroTag: avatarHeroTag,
                onTap: () => onTapAvatar(avatarUrl, avatarHeroTag),
              ),
              if (nickname.trim().isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: DearColors.secondary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(left: bubbleIndent),
          child: child,
        ),
      ],
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({
    required this.imageUrl,
    required this.heroTag,
    required this.onTap,
  });

  final String? imageUrl;
  final String heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatarImageUrl = imageUrl?.trim() ?? '';
    final hasAvatar = avatarImageUrl.isNotEmpty;

    Widget avatarChild;
    if (!hasAvatar) {
      avatarChild =
          const Icon(Icons.favorite, size: 16, color: Color(0xFFE678A9));
    } else {
      avatarChild = Hero(
        tag: heroTag,
        child: Image.network(
          avatarImageUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.favorite,
            size: 16,
            color: Color(0xFFE678A9),
          ),
        ),
      );
    }

    return Tooltip(
      message: hasAvatar ? '상대방 프로필 사진 보기' : '상대방 프로필',
      child: Semantics(
        button: hasAvatar,
        label: hasAvatar ? '상대방 프로필 사진 보기' : '상대방 프로필',
        child: GestureDetector(
          onTap: hasAvatar ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: ClipOval(child: avatarChild),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageMetaRow extends StatelessWidget {
  const _MessageMetaRow({
    required this.isMine,
    required this.deliveryLabel,
    required this.showTimeLabel,
    required this.timeLabel,
    required this.heartCount,
    required this.isHeartedByMe,
    required this.onToggleHeart,
  });

  final bool isMine;
  final String? deliveryLabel;
  final bool showTimeLabel;
  final String timeLabel;
  final int heartCount;
  final bool isHeartedByMe;
  final VoidCallback onToggleHeart;

  @override
  Widget build(BuildContext context) {
    final time = Text(
      timeLabel,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: DearColors.secondary,
            fontWeight: FontWeight.w600,
          ),
    );

    final heart = _HeartReactionButton(
      count: heartCount,
      isActive: isHeartedByMe,
      onTap: onToggleHeart,
    );
    final delivery = deliveryLabel == null
        ? null
        : Text(
            deliveryLabel!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: deliveryLabel == '읽음'
                      ? DearColors.coralText
                      : DearColors.secondary,
                  fontWeight: FontWeight.w700,
                ),
          );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(right: isMine ? 2 : 0, left: isMine ? 0 : 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: isMine
              ? [
                  if (delivery != null) delivery,
                  if (delivery != null) const SizedBox(width: 6),
                  if (showTimeLabel) time,
                  if (showTimeLabel) const SizedBox(width: 6),
                  heart,
                ]
              : [
                  heart,
                  if (showTimeLabel) const SizedBox(width: 6),
                  if (showTimeLabel) time,
                ],
        ),
      ),
    );
  }
}

class _HeartReactionButton extends StatefulWidget {
  const _HeartReactionButton({
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  final int count;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_HeartReactionButton> createState() => _HeartReactionButtonState();
}

class _HeartReactionButtonState extends State<_HeartReactionButton> {
  bool _pressed = false;
  bool _longPulse = false;

  @override
  Widget build(BuildContext context) {
    const activeColor = DearColors.coral;
    const iconSize = 15.0;
    const horizontalPadding = 7.0;
    const verticalPadding = 3.0;

    final label = widget.isActive ? '하트 취소' : '하트 남기기';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onLongPressStart: (_) {
            HapticFeedback.mediumImpact();
            setState(() {
              _pressed = true;
              _longPulse = true;
            });
          },
          onLongPressEnd: (_) => setState(() {
            _pressed = false;
            _longPulse = false;
          }),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutBack,
                scale: _longPulse ? 1.2 : (_pressed ? 0.93 : 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? activeColor.withValues(alpha: 0.18)
                        : DearColors.blush.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(999),
                    border: widget.isActive
                        ? Border.all(
                            color: activeColor.withValues(alpha: 0.28),
                            width: 0.7,
                          )
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.isActive
                            ? Icons.favorite
                            : Icons.favorite_border,
                        size: iconSize,
                        color: widget.isActive
                            ? activeColor
                            : DearColors.secondary,
                      ),
                      if (widget.count > 0) ...[
                        const SizedBox(width: 3),
                        Text(
                          '${widget.count}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: DearColors.secondary,
                                    fontWeight: widget.isActive
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageImageMosaic extends StatelessWidget {
  const _MessageImageMosaic({
    required this.messages,
    required this.isMine,
    required this.showTimeLabel,
    required this.maxWidth,
  });

  final List<ChatMessage> messages;
  final bool isMine;
  final bool showTimeLabel;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tileWidth = (maxWidth - 4) / 2;
    return Semantics(
      label: '사진 ${messages.length}장 묶음',
      child: Column(
        key: ValueKey<String>('chat-image-mosaic-${messages.first.id}'),
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: maxWidth,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final message in messages)
                  _MessageImage(
                    imagePath: message.imagePath!,
                    messageId: message.id,
                    sentAt: message.createdAt,
                    isMine: isMine,
                    showTimeLabel: false,
                    maxWidth: tileWidth,
                  ),
              ],
            ),
          ),
          if (showTimeLabel)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 2),
              child: Text(
                chatTimeLabel(messages.last.createdAt),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: DearColors.secondary,
                      fontWeight: isMine ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageImage extends ConsumerStatefulWidget {
  const _MessageImage({
    required this.imagePath,
    required this.messageId,
    required this.sentAt,
    required this.isMine,
    required this.showTimeLabel,
    required this.maxWidth,
  });

  final String imagePath;
  final int messageId;
  final DateTime sentAt;
  final bool isMine;
  final bool showTimeLabel;
  final double maxWidth;

  @override
  ConsumerState<_MessageImage> createState() => _MessageImageState();
}

class _MessageImageState extends ConsumerState<_MessageImage> {
  static final Map<String, _CachedSignedImageUrl> _signedUrlCache =
      <String, _CachedSignedImageUrl>{};
  static final Map<String, Future<String>> _inflightSignedUrlRequests =
      <String, Future<String>>{};
  static const Duration _signedUrlRefreshInterval = Duration(minutes: 55);

  late Future<String> _signedUrlFuture;

  @override
  void initState() {
    super.initState();
    _signedUrlFuture = _resolveSignedUrl(widget.imagePath);
  }

  @override
  void didUpdateWidget(covariant _MessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _signedUrlFuture = _resolveSignedUrl(widget.imagePath);
    }
  }

  Future<String> _resolveSignedUrl(String imagePath) {
    final now = DateTime.now();
    final cached = _signedUrlCache[imagePath];
    if (cached != null &&
        now.difference(cached.issuedAt) < _signedUrlRefreshInterval) {
      return Future<String>.value(cached.url);
    }

    final inflight = _inflightSignedUrlRequests[imagePath];
    if (inflight != null) {
      return inflight;
    }

    final request =
        ref.read(chatResolveImageUrlProvider)(imagePath).then((url) {
      _signedUrlCache[imagePath] = _CachedSignedImageUrl(
        url: url,
        issuedAt: DateTime.now(),
      );
      _inflightSignedUrlRequests.remove(imagePath);
      return url;
    }).catchError((error) {
      _inflightSignedUrlRequests.remove(imagePath);
      throw error;
    });

    _inflightSignedUrlRequests[imagePath] = request;
    return request;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _signedUrlFuture,
      builder: (context, snapshot) {
        final imageUrl = snapshot.data;
        final heroTag = 'chat-image-${widget.messageId}';

        return GestureDetector(
          onTap: imageUrl == null
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatImageViewPage(
                        imageUrl: imageUrl,
                        heroTag: heroTag,
                      ),
                    ),
                  );
                },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Hero(
                tag: heroTag,
                child: _StableNetworkImageFrame(
                  imageUrl: imageUrl,
                  width: widget.maxWidth,
                  height: widget.maxWidth * 0.74,
                  borderRadius: 12,
                ),
              ),
              if (widget.showTimeLabel)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 2),
                  child: Text(
                    chatTimeLabel(widget.sentAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: DearColors.secondary,
                          fontWeight:
                              widget.isMine ? FontWeight.w600 : FontWeight.w500,
                        ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StableNetworkImageFrame extends StatelessWidget {
  const _StableNetworkImageFrame({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final String? imageUrl;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: BoxDecoration(
        color: DearColors.blush,
        border: Border.all(color: DearColors.line),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Icon(
          Icons.image_rounded,
          color: DearColors.coral.withValues(alpha: 0.6),
          size: 30,
        ),
      ),
    );

    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: imageUrl == null
            ? placeholder
            : Stack(
                fit: StackFit.expand,
                children: [
                  placeholder,
                  Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    loadingBuilder: (context, child, loadingProgress) => child,
                    errorBuilder: (context, error, stackTrace) {
                      return const DecoratedBox(
                        decoration: BoxDecoration(color: DearColors.blush),
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: DearColors.disabled,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

class _CachedSignedImageUrl {
  const _CachedSignedImageUrl({
    required this.url,
    required this.issuedAt,
  });

  final String url;
  final DateTime issuedAt;
}
