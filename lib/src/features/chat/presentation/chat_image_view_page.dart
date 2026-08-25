import 'dart:typed_data';

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
  _ImageAction? _busyAction;

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

  Future<Uint8List> _bytesForCurrentImage() async {
    final url = _imageUrls[_currentIndex];
    final cached = _downloadedBytes[url];
    if (cached != null) return cached;
    final bytes = await ref.read(chatFetchImageBytesProvider)(url);
    _downloadedBytes[url] = bytes;
    return bytes;
  }

  String _baseNameForCurrentImage() {
    return 'dear_${DateTime.now().millisecondsSinceEpoch}_${_currentIndex + 1}';
  }

  Future<void> _saveCurrentImage() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = _ImageAction.save);
    try {
      final bytes = await _bytesForCurrentImage();
      final result = await ref.read(chatSaveImageProvider)(
        bytes: bytes,
        name: _baseNameForCurrentImage(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  Future<void> _shareCurrentImage() async {
    if (_busyAction != null) return;
    setState(() => _busyAction = _ImageAction.share);
    try {
      final url = _imageUrls[_currentIndex];
      final extension = chatImageExtensionFromUrl(url);
      final bytes = await _bytesForCurrentImage();
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      final origin =
          box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await ref.read(chatShareImageProvider)(
        bytes: bytes,
        filename: '${_baseNameForCurrentImage()}.$extension',
        mimeType: chatImageMimeType(extension),
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사진을 공유하지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busyAction = null);
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
          total > 1 ? '이미지 보기 ${_currentIndex + 1}/$total' : '이미지 보기',
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _imageUrls.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Hero(
                tag: _heroTags[index],
                child: Image.network(
                  _imageUrls[index],
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '이미지를 불러오지 못했어요.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  },
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
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('chat-image-save'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                ),
                onPressed: _busyAction == null ? _saveCurrentImage : null,
                icon: _busyAction == _ImageAction.save
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
                  side: const BorderSide(color: Colors.white38),
                ),
                onPressed: _busyAction == null ? _shareCurrentImage : null,
                icon: _busyAction == _ImageAction.share
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
        ),
      ),
    );
  }
}

enum _ImageAction { save, share }
