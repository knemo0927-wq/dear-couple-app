import 'dart:async';

import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_providers.dart';
import 'package:couple_chat_app/src/features/chat/data/chat_repository.dart';
import 'package:couple_chat_app/src/features/chat/presentation/chat_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatSearchPage extends ConsumerStatefulWidget {
  const ChatSearchPage({required this.coupleId, super.key});

  final String coupleId;

  @override
  ConsumerState<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends ConsumerState<ChatSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  List<ChatMessage> _results = const <ChatMessage>[];
  String? _snapshotQuery;
  int _selectedIndex = -1;
  int _requestGeneration = 0;
  bool _loading = false;
  bool _retrying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _requestGeneration++;
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _requestGeneration++;
    final query = value.trim();
    setState(() {
      _loading = false;
      _retrying = false;
      _error = null;
      if (query.isEmpty) {
        _results = const <ChatMessage>[];
        _snapshotQuery = null;
        _selectedIndex = -1;
      }
    });
    if (query.isEmpty) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search({bool retry = false}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final requestGeneration = ++_requestGeneration;
    final keepInlineError = retry && _snapshotQuery != null && _error != null;
    setState(() {
      _loading = true;
      _retrying = keepInlineError;
      if (!keepInlineError) _error = null;
    });
    try {
      final results = await ref.read(chatSearchMessagesProvider)(
        coupleId: widget.coupleId,
        query: query,
      );
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _results = List<ChatMessage>.unmodifiable(results);
        _snapshotQuery = query;
        _selectedIndex = results.isEmpty ? -1 : 0;
        _loading = false;
        _retrying = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || requestGeneration != _requestGeneration) return;
      setState(() {
        _loading = false;
        _retrying = false;
        _error = toFriendlyErrorMessage(error);
      });
    }
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    final next = (_selectedIndex + delta).clamp(0, _results.length - 1);
    if (next == _selectedIndex) return;
    setState(() => _selectedIndex = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = (next * 96.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: DearMotion.standard,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.watch(chatCurrentUserIdProvider);
    final currentInput = _controller.text.trim();
    final snapshotQuery = _snapshotQuery;
    return Scaffold(
      appBar: AppBar(title: const Text('메시지 검색')),
      body: DearBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SearchBar(
                key: const Key('chat-search-field'),
                controller: _controller,
                focusNode: _focusNode,
                hintText: '대화 내용 검색',
                leading: const Icon(Icons.search_rounded),
                trailing: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      tooltip: '검색어 지우기',
                      onPressed: () {
                        _controller.clear();
                        _scheduleSearch('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
                onChanged: _scheduleSearch,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  _search();
                },
              ),
            ),
            if (snapshotQuery != null &&
                currentInput.isNotEmpty &&
                _results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        label: snapshotQuery == currentInput
                            ? '검색 결과 ${_results.length}개 중 ${_selectedIndex + 1}번째'
                            : '$snapshotQuery 이전 검색 결과 ${_results.length}개 중 ${_selectedIndex + 1}번째',
                        child: ExcludeSemantics(
                          child: Text(
                            snapshotQuery == currentInput
                                ? '${_results.length}개의 결과 · ${_selectedIndex + 1}번째'
                                : '“$snapshotQuery” 결과 ${_results.length}개 · ${_selectedIndex + 1}번째',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '이전 검색 결과',
                      onPressed:
                          _selectedIndex > 0 ? () => _moveSelection(-1) : null,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    ),
                    IconButton(
                      tooltip: '다음 검색 결과',
                      onPressed: _selectedIndex < _results.length - 1
                          ? () => _moveSelection(1)
                          : null,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _SearchBody(
                controller: _scrollController,
                snapshotQuery: snapshotQuery,
                currentInput: currentInput,
                loading: _loading,
                retrying: _retrying,
                error: _error,
                results: _results,
                selectedIndex: _selectedIndex,
                myUserId: myUserId,
                onRetry: () => _search(retry: true),
                onSelect: (index) => setState(() => _selectedIndex = index),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.controller,
    required this.snapshotQuery,
    required this.currentInput,
    required this.loading,
    required this.retrying,
    required this.error,
    required this.results,
    required this.selectedIndex,
    required this.myUserId,
    required this.onRetry,
    required this.onSelect,
  });

  final ScrollController controller;
  final String? snapshotQuery;
  final String currentInput;
  final bool loading;
  final bool retrying;
  final String? error;
  final List<ChatMessage> results;
  final int selectedIndex;
  final String? myUserId;
  final VoidCallback onRetry;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (currentInput.isEmpty) {
      return const _SearchEmptyState(
        icon: Icons.manage_search_rounded,
        title: '찾고 싶은 대화를 입력해 주세요',
        description: '메시지 내용에서 검색해요.',
      );
    }

    final query = snapshotQuery;
    if (query == null) {
      if (loading) {
        return const Center(
          child: DearLoadingState(label: '대화를 찾고 있어요...'),
        );
      }
      if (error != null) {
        return _SearchBlockingError(error: error!, onRetry: onRetry);
      }
      return const _SearchEmptyState(
        icon: Icons.manage_search_rounded,
        title: '검색을 준비하고 있어요',
        description: '입력을 멈추면 대화에서 자동으로 찾아요.',
      );
    }

    final showingPreviousQuery = query != currentInput;
    final content = results.isEmpty
        ? _SearchEmptyState(
            key: const Key('chat-search-empty-success'),
            icon: Icons.chat_bubble_outline_rounded,
            title: showingPreviousQuery ? '“$query” 검색 결과가 없어요' : '검색 결과가 없어요',
            description: '다른 검색어로 다시 찾아보세요.',
            liveRegion: !loading && error == null && !showingPreviousQuery,
            semanticLabel: '$query 검색 결과 없음',
          )
        : ListView.separated(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: results.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final message = results[index];
              final selected = index == selectedIndex;
              return Semantics(
                selected: selected,
                button: true,
                label: '${index + 1}번째 검색 결과',
                child: DearCard(
                  key: ValueKey<String>('chat-search-result-${message.id}'),
                  padding: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(DearRadii.large),
                    onTap: () => onSelect(index),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(DearRadii.large),
                        border: selected
                            ? Border.all(
                                color: Theme.of(context).colorScheme.outline,
                              )
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                message.senderId == myUserId ? '나' : '상대',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const Spacer(),
                              Text(
                                '${chatDateLabel(message.createdAt)} ${chatTimeLabel(message.createdAt)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _HighlightedText(
                              text: message.body ?? '', query: query),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: DearInlineError(
              key: const Key('chat-search-inline-error'),
              message: error!,
              onRetry: onRetry,
              retrying: retrying,
            ),
          )
        else if (loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: DearInlineLoading(
              key: const Key('chat-search-inline-loading'),
              label: '“$currentInput” 대화를 찾고 있어요...',
            ),
          ),
        if (showingPreviousQuery)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Semantics(
              key: const Key('chat-search-preserved-query'),
              container: true,
              liveRegion: true,
              label: '현재 검색어는 $currentInput입니다. $query 이전 검색 결과를 유지하고 있습니다.',
              child: ExcludeSemantics(
                child: Text(
                  '현재 “$currentInput” 검색 중 · “$query” 이전 결과 표시',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ),
        Expanded(child: content),
      ],
    );
  }
}

class _SearchBlockingError extends StatelessWidget {
  const _SearchBlockingError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Center(
        child: DearCard(
          margin: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExcludeSemantics(
                child: Icon(Icons.search_off_rounded, size: 42),
              ),
              const SizedBox(height: 10),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final source = text.toLowerCase();
    final target = query.toLowerCase();
    final spans = <TextSpan>[];
    var cursor = 0;
    while (target.isNotEmpty) {
      final index = source.indexOf(target, cursor);
      if (index < 0) break;
      if (index > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + target.length),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w900,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          ),
        ),
      );
      cursor = index + target.length;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.4,
            ),
        children: spans,
      ),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.liveRegion = false,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool liveRegion;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DearIconBubble(icon: icon, size: 62),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
    if (!liveRegion) return content;
    return Semantics(
      container: true,
      liveRegion: true,
      label: semanticLabel ?? '$title. $description',
      child: ExcludeSemantics(child: content),
    );
  }
}
