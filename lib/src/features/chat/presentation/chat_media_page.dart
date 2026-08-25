import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_format.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_image_view_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatMediaPage extends ConsumerStatefulWidget {
  const ChatMediaPage({required this.coupleId, super.key});

  final String coupleId;

  @override
  ConsumerState<ChatMediaPage> createState() => _ChatMediaPageState();
}

class _ChatMediaPageState extends ConsumerState<ChatMediaPage> {
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 280) _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!reset && !_hasMore)) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _messages.clear();
        _hasMore = true;
      }
    });
    try {
      final page = await ref.read(chatFetchMediaPageProvider)(
        coupleId: widget.coupleId,
        beforeMessageId: reset || _messages.isEmpty ? null : _messages.last.id,
      );
      if (!mounted) return;
      final seen = _messages.map((message) => message.id).toSet();
      setState(() {
        _messages.addAll(
          page.messages.where((message) => seen.add(message.id)),
        );
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = toFriendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사진 모아보기')),
      body: DearBackground(
        child: RefreshIndicator(
          onRefresh: () => _load(reset: true),
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading && _messages.isEmpty) {
      return GridView.builder(
        key: const Key('chat-media-loading'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: 12,
        itemBuilder: (_, __) => DecoratedBox(
          decoration: BoxDecoration(
            color: DearColors.blush,
            borderRadius: BorderRadius.circular(DearRadii.small),
          ),
        ),
      );
    }
    if (_error != null && _messages.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          DearCard(
            child: Column(
              children: [
                const DearIconBubble(icon: Icons.broken_image_outlined),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _load(reset: true),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_messages.isEmpty) {
      return ListView(
        key: const Key('chat-media-empty'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 110),
          const DearIconBubble(icon: Icons.photo_library_outlined, size: 68),
          const SizedBox(height: 14),
          Text(
            '아직 주고받은 사진이 없어요',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: DearColors.ink,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '채팅에서 사진을 보내면 이곳에 모여요.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DearColors.secondary,
                ),
          ),
        ],
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: _messages.length,
            itemBuilder: (context, index) => _MediaTile(
              key: ValueKey<int>(_messages[index].id),
              message: _messages[index],
              resolveUrl: ref.read(chatResolveImageUrlProvider),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _error != null
                      ? TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('사진을 더 불러오지 못했어요 · 다시 시도'),
                        )
                      : !_hasMore
                          ? const Text('모든 사진을 불러왔어요.')
                          : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _MediaTile extends StatefulWidget {
  const _MediaTile({
    required this.message,
    required this.resolveUrl,
    super.key,
  });

  final ChatMessage message;
  final ChatResolveImageUrl resolveUrl;

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = widget.resolveUrl(widget.message.imagePath!);
  }

  void _retry() => setState(() {
        _urlFuture = widget.resolveUrl(widget.message.imagePath!);
      });

  @override
  Widget build(BuildContext context) {
    final heroTag = 'chat-media-${widget.message.id}';
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        final url = snapshot.data;
        return Semantics(
          button: url != null,
          label: '${chatDateLabel(widget.message.createdAt)}에 주고받은 사진',
          child: Material(
            key: ValueKey<String>('chat-media-${widget.message.id}'),
            color: DearColors.blush,
            borderRadius: BorderRadius.circular(DearRadii.small),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: url == null
                  ? (snapshot.hasError ? _retry : null)
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatImageViewPage(
                            imageUrl: url,
                            heroTag: heroTag,
                          ),
                        ),
                      ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null)
                    Hero(
                      tag: heroTag,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: DearColors.disabled,
                        ),
                      ),
                    )
                  else if (snapshot.hasError)
                    const Icon(
                      Icons.refresh_rounded,
                      color: DearColors.secondary,
                    )
                  else
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Positioned(
                    left: 5,
                    right: 5,
                    bottom: 4,
                    child: Text(
                      chatDateLabel(widget.message.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 5),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
