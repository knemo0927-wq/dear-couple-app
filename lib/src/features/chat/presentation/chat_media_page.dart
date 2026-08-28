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
  _MediaLoadPhase _loadPhase = _MediaLoadPhase.idle;
  bool _hasLoadedOnce = false;
  bool _hasMore = true;
  String? _initialError;
  String? _refreshError;
  String? _loadMoreError;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 280) _loadMore();
  }

  Future<void> _loadInitial() async {
    if (_loadPhase != _MediaLoadPhase.idle) return;
    setState(() {
      _loadPhase = _MediaLoadPhase.initial;
    });
    try {
      final page = await ref.read(chatFetchMediaPageProvider)(
        coupleId: widget.coupleId,
        beforeMessageId: null,
      );
      if (!mounted) return;
      final replacement = _dedupeMessages(page.messages);
      setState(() {
        _messages
          ..clear()
          ..addAll(replacement);
        _hasMore = page.hasMore;
        _hasLoadedOnce = true;
        _initialError = null;
        _refreshError = null;
        _loadMoreError = null;
        _loadPhase = _MediaLoadPhase.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initialError = toFriendlyErrorMessage(error);
        _loadPhase = _MediaLoadPhase.idle;
      });
    }
  }

  Future<void> _refresh() async {
    if (_loadPhase != _MediaLoadPhase.idle) return;
    setState(() => _loadPhase = _MediaLoadPhase.refresh);
    try {
      final page = await ref.read(chatFetchMediaPageProvider)(
        coupleId: widget.coupleId,
        beforeMessageId: null,
      );
      if (!mounted) return;
      final replacement = _dedupeMessages(page.messages);
      setState(() {
        _messages
          ..clear()
          ..addAll(replacement);
        _hasMore = page.hasMore;
        _hasLoadedOnce = true;
        _initialError = null;
        _refreshError = null;
        _loadMoreError = null;
        _loadPhase = _MediaLoadPhase.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _refreshError = toFriendlyErrorMessage(error);
        _loadPhase = _MediaLoadPhase.idle;
      });
    }
  }

  Future<void> _loadMore({bool retry = false}) async {
    if (_loadPhase != _MediaLoadPhase.idle ||
        !_hasLoadedOnce ||
        !_hasMore ||
        (_loadMoreError != null && !retry)) {
      return;
    }
    setState(() => _loadPhase = _MediaLoadPhase.loadMore);
    try {
      final page = await ref.read(chatFetchMediaPageProvider)(
        coupleId: widget.coupleId,
        beforeMessageId: _messages.isEmpty ? null : _messages.last.id,
      );
      if (!mounted) return;
      final seen = _messages.map((message) => message.id).toSet();
      final additions = _dedupeMessages(page.messages, seen: seen);
      setState(() {
        _messages.addAll(additions);
        _hasMore = page.hasMore;
        _loadMoreError = null;
        _loadPhase = _MediaLoadPhase.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadMoreError = toFriendlyErrorMessage(error);
        _loadPhase = _MediaLoadPhase.idle;
      });
    }
  }

  List<ChatMessage> _dedupeMessages(
    Iterable<ChatMessage> messages, {
    Set<int>? seen,
  }) {
    final ids = seen ?? <int>{};
    return [
      for (final message in messages)
        if (ids.add(message.id)) message,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사진 모아보기')),
      body: DearBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_hasLoadedOnce && _initialError != null) {
      return ListView(
        key: const Key('chat-media-initial-error'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(DearSpacing.space24),
        children: [
          const SizedBox(height: 120),
          DearInlineError(
            message: _initialError!,
            onRetry: _loadInitial,
            retrying: _loadPhase == _MediaLoadPhase.initial,
          ),
        ],
      );
    }

    if (!_hasLoadedOnce) {
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
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(DearRadii.small),
          ),
        ),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_refreshError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DearSpacing.space12,
                DearSpacing.space12,
                DearSpacing.space12,
                0,
              ),
              child: DearInlineError(
                key: const Key('chat-media-refresh-error'),
                message: _refreshError!,
                onRetry: _refresh,
                retrying: _loadPhase == _MediaLoadPhase.refresh,
              ),
            ),
          )
        else if (_loadPhase == _MediaLoadPhase.refresh)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                DearSpacing.space12,
                DearSpacing.space12,
                DearSpacing.space12,
                0,
              ),
              child: DearInlineLoading(
                key: Key('chat-media-refresh-loading'),
                label: '사진 목록을 새로고침하는 중',
              ),
            ),
          ),
        if (_messages.isEmpty)
          const SliverFillRemaining(
            key: Key('chat-media-empty'),
            hasScrollBody: false,
            child: DearEmptyState(
              title: '아직 주고받은 사진이 없어요',
              message: '채팅에서 사진을 보내면 이곳에 모여요.',
              icon: Icons.photo_library_outlined,
            ),
          )
        else ...[
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
          SliverToBoxAdapter(child: _buildLoadMoreFooter()),
        ],
      ],
    );
  }

  Widget _buildLoadMoreFooter() {
    if (_loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(DearSpacing.space12),
        child: DearInlineError(
          key: const Key('chat-media-load-more-error'),
          message: _loadMoreError!,
          onRetry: () => _loadMore(retry: true),
          retrying: _loadPhase == _MediaLoadPhase.loadMore,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: _loadPhase == _MediaLoadPhase.loadMore
            ? Semantics(
                label: '사진을 더 불러오는 중',
                liveRegion: true,
                child: const ExcludeSemantics(
                  child: SizedBox(
                    key: Key('chat-media-load-more-loading'),
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : !_hasMore
                ? const Text('모든 사진을 불러왔어요.')
                : const SizedBox.shrink(),
      ),
    );
  }
}

enum _MediaLoadPhase { idle, initial, refresh, loadMore }

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
  String? _resolvedUrl;
  bool _retrying = false;
  int _imageRevision = 0;

  @override
  void initState() {
    super.initState();
    _urlFuture = _resolveUrl();
  }

  @override
  void didUpdateWidget(covariant _MediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.imagePath != widget.message.imagePath ||
        oldWidget.resolveUrl != widget.resolveUrl) {
      _resolvedUrl = null;
      _imageRevision += 1;
      _urlFuture = _resolveUrl();
    }
  }

  Future<String> _resolveUrl() async {
    final url = (await widget.resolveUrl(widget.message.imagePath!)).trim();
    if (url.isEmpty) throw StateError('Empty chat image URL');
    _resolvedUrl = url;
    return url;
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);

    final previousUrl = _resolvedUrl;
    if (previousUrl != null) {
      try {
        await NetworkImage(previousUrl).evict();
      } catch (_) {
        // URL refresh remains useful even if the stale cache entry is absent.
      }
    }
    if (!mounted) return;

    final refreshedFuture = _resolveUrl();
    setState(() {
      _resolvedUrl = null;
      _imageRevision += 1;
      _urlFuture = refreshedFuture;
    });
    try {
      await refreshedFuture;
    } catch (_) {
      // FutureBuilder exposes the refreshed failure with the same retry action.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  void _openImage(String url, String heroTag) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatImageViewPage(
          imageUrl: url,
          heroTag: heroTag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = 'chat-media-${widget.message.id}';
    final dateLabel = chatDateLabel(widget.message.createdAt);
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snapshot) {
        Widget child;
        if (snapshot.connectionState != ConnectionState.done) {
          child = _MediaLoadingFrame(
            dateLabel: dateLabel,
            retrying: _retrying,
          );
        } else if (snapshot.hasError || snapshot.data == null) {
          child = _MediaRetryFrame(
            messageId: widget.message.id,
            dateLabel: dateLabel,
            retrying: _retrying,
            onRetry: _retry,
          );
        } else {
          final url = snapshot.data!;
          child = Image.network(
            url,
            key: ValueKey<String>(
              'chat-media-network-image-${widget.message.id}-$_imageRevision',
            ),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            frameBuilder: (context, image, frame, synchronous) {
              if (!synchronous && frame == null) {
                return _MediaLoadingFrame(dateLabel: dateLabel);
              }
              return Semantics(
                button: true,
                label: '$dateLabel에 주고받은 사진',
                onTap: () => _openImage(url, heroTag),
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => _openImage(url, heroTag),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(tag: heroTag, child: image),
                      _MediaDateOverlay(dateLabel: dateLabel),
                    ],
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => _MediaRetryFrame(
              messageId: widget.message.id,
              dateLabel: dateLabel,
              retrying: _retrying,
              onRetry: _retry,
            ),
          );
        }

        return Material(
          key: ValueKey<String>('chat-media-${widget.message.id}'),
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(DearRadii.small),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
    );
  }
}

class _MediaLoadingFrame extends StatelessWidget {
  const _MediaLoadingFrame({
    required this.dateLabel,
    this.retrying = false,
  });

  final String dateLabel;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    final label = retrying ? '사진을 다시 불러오는 중' : '사진을 불러오는 중';
    return Semantics(
      label: label,
      liveRegion: retrying,
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            _MediaDateOverlay(dateLabel: dateLabel),
          ],
        ),
      ),
    );
  }
}

class _MediaRetryFrame extends StatelessWidget {
  const _MediaRetryFrame({
    required this.messageId,
    required this.dateLabel,
    required this.retrying,
    required this.onRetry,
  });

  final int messageId;
  final String dateLabel;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Semantics(
            key: ValueKey<String>('chat-media-image-retry-$messageId'),
            container: true,
            button: true,
            enabled: !retrying,
            liveRegion: retrying,
            label: retrying ? '사진 다시 불러오는 중' : '사진 다시 불러오기',
            onTap: retrying ? null : onRetry,
            excludeSemantics: true,
            child: TextButton.icon(
              onPressed: retrying ? null : onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  DearTouchTargets.minimum,
                  DearTouchTargets.minimum,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: retrying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(retrying ? '불러오는 중' : '다시 시도'),
            ),
          ),
        ),
        _MediaDateOverlay(dateLabel: dateLabel),
      ],
    );
  }
}

class _MediaDateOverlay extends StatelessWidget {
  const _MediaDateOverlay({required this.dateLabel});

  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 5,
      right: 5,
      bottom: 4,
      child: ExcludeSemantics(
        child: Text(
          dateLabel,
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
    );
  }
}
