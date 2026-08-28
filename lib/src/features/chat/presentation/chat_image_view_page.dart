import 'dart:typed_data';

import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_image_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatImageViewPage extends ConsumerStatefulWidget {
  const ChatImageViewPage({
    required this.imageUrl,
    required this.heroTag,
    this.imageUrls,
    this.heroTags,
    this.initialIndex = 0,
    super.key,
  });

  final String imageUrl;
  final String heroTag;
  final List<String>? imageUrls;
  final List<String>? heroTags;
  final int initialIndex;

  @override
  ConsumerState<ChatImageViewPage> createState() => _ChatImageViewPageState();
}

class _ChatImageViewPageState extends ConsumerState<ChatImageViewPage> {
  late final List<String> _imageUrls;
  late final List<String> _heroTags;
  late final PageController _pageController;
  late int _currentIndex;
  final Map<String, Uint8List> _downloadedBytes = <String, Uint8List>{};
  _PendingImageAction? _busyAction;
  _ImageActionFailure? _actionFailure;

  @override
  void initState() {
    super.initState();

    _imageUrls = (widget.imageUrls != null && widget.imageUrls!.isNotEmpty)
        ? List<String>.from(widget.imageUrls!)
        : <String>[widget.imageUrl];

    if (widget.heroTags != null &&
        widget.heroTags!.length == _imageUrls.length) {
      _heroTags = List<String>.from(widget.heroTags!);
    } else {
      _heroTags = List<String>.generate(
        _imageUrls.length,
        (index) => index == 0 ? widget.heroTag : '${widget.heroTag}-$index',
      );
    }

    _currentIndex = widget.initialIndex.clamp(0, _imageUrls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<Uint8List> _bytesForImage(int index) async {
    final url = _imageUrls[index];
    final cached = _downloadedBytes[url];
    if (cached != null) return cached;
    final bytes = await ref.read(chatFetchImageBytesProvider)(url);
    _downloadedBytes[url] = bytes;
    return bytes;
  }

  String _baseNameForImage(int index) {
    return 'dear_${DateTime.now().millisecondsSinceEpoch}_${index + 1}';
  }

  Future<void> _saveCurrentImage([int? requestedIndex]) async {
    if (_busyAction != null) return;
    final targetIndex = requestedIndex ?? _currentIndex;
    setState(() {
      _busyAction = _PendingImageAction(
        action: _ImageAction.save,
        index: targetIndex,
      );
    });
    try {
      final bytes = await _bytesForImage(targetIndex);
      final result = await ref.read(chatSaveImageProvider)(
        bytes: bytes,
        name: _baseNameForImage(targetIndex),
      );
      if (!mounted) return;
      final message = switch (result) {
        ChatImageSaveResult.saved => '사진 보관함에 저장했어요.',
        ChatImageSaveResult.permissionDenied =>
          '사진 접근 권한이 필요해요. 기기 설정에서 권한을 허용해 주세요.',
        ChatImageSaveResult.unsupported =>
          '이 기기에서는 직접 저장을 지원하지 않아요. 공유를 이용해 주세요.',
        ChatImageSaveResult.notEnoughSpace => '기기 저장 공간이 부족해요.',
        ChatImageSaveResult.unsupportedFormat => '저장할 수 없는 이미지 형식이에요.',
      };
      setState(() {
        _actionFailure = result == ChatImageSaveResult.saved
            ? null
            : _ImageActionFailure(
                action: _ImageAction.save,
                index: targetIndex,
                message: message,
                retryable: false,
              );
      });
      if (result == ChatImageSaveResult.saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionFailure = _ImageActionFailure(
          action: _ImageAction.save,
          index: targetIndex,
          message: '사진을 저장하지 못했어요.',
          retryable: true,
        );
      });
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _shareCurrentImage([int? requestedIndex]) async {
    if (_busyAction != null) return;
    final targetIndex = requestedIndex ?? _currentIndex;
    setState(() {
      _busyAction = _PendingImageAction(
        action: _ImageAction.share,
        index: targetIndex,
      );
    });
    try {
      final url = _imageUrls[targetIndex];
      final extension = chatImageExtensionFromUrl(url);
      final bytes = await _bytesForImage(targetIndex);
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await ref.read(chatShareImageProvider)(
        bytes: bytes,
        filename: '${_baseNameForImage(targetIndex)}.$extension',
        mimeType: chatImageMimeType(extension),
        sharePositionOrigin: origin,
      );
      if (mounted) setState(() => _actionFailure = null);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _actionFailure = _ImageActionFailure(
          action: _ImageAction.share,
          index: targetIndex,
          message: '사진을 공유하지 못했어요.',
          retryable: true,
        );
      });
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _retryActionFailure(_ImageActionFailure failure) {
    if (_busyAction != null) return Future<void>.value();
    switch (failure.action) {
      case _ImageAction.save:
        return _saveCurrentImage(failure.index);
      case _ImageAction.share:
        return _shareCurrentImage(failure.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _imageUrls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          total > 1 ? '이미지 보기 ${_currentIndex + 1} / $total' : '이미지 보기',
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _imageUrls.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return Semantics(
            container: true,
            image: true,
            label: total == 1
                ? '사진. 두 손가락으로 확대할 수 있어요.'
                : '${index + 1}번째 사진, 전체 $total장. '
                    '두 손가락으로 확대하고 좌우로 넘길 수 있어요.',
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Hero(
                  tag: _heroTags[index],
                  child: _RetryableNetworkImage(
                    imageUrl: _imageUrls[index],
                    index: index,
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_actionFailure case final failure?
                  when failure.index == _currentIndex) ...[
                DearInlineError(
                  message: failure.message,
                  onRetry: failure.retryable
                      ? () => _retryActionFailure(failure)
                      : null,
                  retrying: _busyAction?.action == failure.action &&
                      _busyAction?.index == failure.index,
                ),
                const SizedBox(height: DearSpacing.space8),
              ],
              if (_busyAction case final busy?)
                Semantics(
                  liveRegion: true,
                  label: '${busy.index + 1}번째 사진 '
                      '${busy.action == _ImageAction.save ? '저장' : '공유'} 중',
                  child: const SizedBox.shrink(),
                ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('chat-image-save'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      minimumSize: const Size(
                        DearTouchTargets.minimum,
                        DearTouchTargets.minimum,
                      ),
                    ),
                    onPressed: _busyAction == null ? _saveCurrentImage : null,
                    icon: _busyAction?.action == _ImageAction.save
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.download_rounded),
                    label: const Text('저장'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('chat-image-share'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      minimumSize: const Size(
                        DearTouchTargets.minimum,
                        DearTouchTargets.minimum,
                      ),
                    ),
                    onPressed: _busyAction == null ? _shareCurrentImage : null,
                    icon: _busyAction?.action == _ImageAction.share
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.ios_share_rounded),
                    label: const Text('공유'),
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

class _RetryableNetworkImage extends StatefulWidget {
  const _RetryableNetworkImage({
    required this.imageUrl,
    required this.index,
  });

  final String imageUrl;
  final int index;

  @override
  State<_RetryableNetworkImage> createState() => _RetryableNetworkImageState();
}

class _RetryableNetworkImageState extends State<_RetryableNetworkImage> {
  int _generation = 0;

  Future<void> _retry() async {
    await NetworkImage(widget.imageUrl).evict();
    if (!mounted) return;
    setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.imageUrl,
      key: ValueKey<String>(
        'chat-image-view-${widget.index}-$_generation',
      ),
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Semantics(
          liveRegion: true,
          label: '이미지를 불러오는 중',
          child: const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(color: Colors.white),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Semantics(
          container: true,
          liveRegion: true,
          label: '이미지를 불러오지 못했어요. 다시 시도할 수 있어요.',
          child: Padding(
            padding: const EdgeInsets.all(DearSpacing.space24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 36,
                  ),
                ),
                const SizedBox(height: DearSpacing.space12),
                const Text(
                  '이미지를 불러오지 못했어요.',
                  style: TextStyle(color: Colors.white),
                ),
                const SizedBox(height: DearSpacing.space8),
                OutlinedButton.icon(
                  key: ValueKey<String>(
                    'chat-image-retry-${widget.index}',
                  ),
                  onPressed: _retry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    minimumSize: const Size(
                      DearTouchTargets.minimum,
                      DearTouchTargets.minimum,
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _ImageAction { save, share }

class _PendingImageAction {
  const _PendingImageAction({
    required this.action,
    required this.index,
  });

  final _ImageAction action;
  final int index;
}

class _ImageActionFailure {
  const _ImageActionFailure({
    required this.action,
    required this.index,
    required this.message,
    required this.retryable,
  });

  final _ImageAction action;
  final int index;
  final String message;
  final bool retryable;
}
