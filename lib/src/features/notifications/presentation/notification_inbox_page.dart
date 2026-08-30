import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_inbox.dart';
import 'package:couple_chat_app/src/features/notifications/data/notification_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NotificationInboxPage extends ConsumerStatefulWidget {
  const NotificationInboxPage({super.key});

  @override
  ConsumerState<NotificationInboxPage> createState() =>
      _NotificationInboxPageState();
}

class _NotificationInboxPageState extends ConsumerState<NotificationInboxPage> {
  bool _markingAll = false;
  bool _retrying = false;
  final Set<String> _openingIds = <String>{};

  Future<void> _markAll(List<String> unreadIds) async {
    if (_markingAll || unreadIds.isEmpty) return;
    setState(() => _markingAll = true);
    try {
      await ref.read(markNotificationReadProvider)(unreadIds);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '읽음 상태를 저장하지 못했어요. ${toFriendlyErrorMessage(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _open(NotificationInboxItem item) async {
    if (_openingIds.contains(item.id)) return;
    final route = sanitizeNotificationRoute(item.route);
    setState(() => _openingIds.add(item.id));

    // 읽음 RPC가 실패해도 사용자가 선택한 알림 딥링크는 즉시 연다.
    if (route != null) context.push(route);
    try {
      await ref.read(markNotificationReadProvider)([item.id]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '알림은 열었지만 읽음 상태를 저장하지 못했어요. '
            '${toFriendlyErrorMessage(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingIds.remove(item.id));
    }
  }

  Future<void> _retry(String userId) async {
    if (_retrying) return;
    setState(() => _retrying = true);
    ref.invalidate(notificationInboxProvider(userId));
    try {
      await ref.read(notificationInboxProvider(userId).future);
    } catch (_) {
      // The provider keeps the original exception and renders it inline.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(authSessionProvider).valueOrNull?.user.id;
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('로그인이 필요합니다.')));
    }
    final inboxAsync = ref.watch(notificationInboxProvider(userId));
    final unreadIds =
        (inboxAsync.valueOrNull ?? const <NotificationInboxItem>[])
            .where((item) => item.isUnread)
            .map((item) => item.id)
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          if (unreadIds.isNotEmpty)
            TextButton(
              onPressed: _markingAll ? null : () => _markAll(unreadIds),
              child: Text(_markingAll ? '저장 중' : '모두 읽음'),
            ),
        ],
      ),
      body: DearBackground(
        child: inboxAsync.when(
          loading: () => const _InboxSkeleton(),
          error: (error, __) => _InboxError(
            message: '알림을 불러오지 못했어요. ${toFriendlyErrorMessage(error)}',
            retrying: _retrying,
            onRetry: () => _retry(userId),
          ),
          data: (items) {
            if (items.isEmpty) return const _InboxEmpty();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = items[index];
                return _InboxTile(
                  item: item,
                  onTap:
                      _openingIds.contains(item.id) ? null : () => _open(item),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.item, required this.onTap});

  final NotificationInboxItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (item.category) {
      'anniversary' => Icons.favorite_rounded,
      'image' => Icons.photo_outlined,
      'game' => Icons.grid_4x4_rounded,
      _ => Icons.chat_bubble_outline_rounded,
    };
    return DearCard(
      key: ValueKey('notification-inbox-${item.id}'),
      padding: EdgeInsets.zero,
      color: item.isUnread ? scheme.primaryContainer : scheme.surface,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(DearRadii.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(DearRadii.medium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                DearIconBubble(
                  icon: icon,
                  size: 48,
                  iconSize: 23,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (item.isUnread)
                            Semantics(
                              label: '읽지 않음',
                              child: CircleAvatar(
                                radius: 4,
                                backgroundColor: scheme.primary,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _timeLabel(item.createdAt),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.78,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 96,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(DearRadii.medium),
        ),
      ),
    );
  }
}

class _InboxEmpty extends StatelessWidget {
  const _InboxEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DearIconBubble(icon: Icons.notifications_none_rounded, size: 64),
          SizedBox(height: 14),
          Text('새로운 알림이 없어요.'),
        ],
      ),
    );
  }
}

class _InboxError extends StatelessWidget {
  const _InboxError({
    required this.message,
    required this.onRetry,
    required this.retrying,
  });

  final String message;
  final VoidCallback onRetry;
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('notification-inbox-error-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(DearSpacing.space24),
      children: [
        const SizedBox(height: 120),
        DearInlineError(
          key: const Key('notification-inbox-error'),
          message: message,
          retryButtonKey: const Key('notification-inbox-retry-button'),
          retrying: retrying,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
  if (difference.inMinutes < 1) return '방금 전';
  if (difference.inHours < 1) return '${difference.inMinutes}분 전';
  if (difference.inDays < 1) return '${difference.inHours}시간 전';
  return '${local.month}월 ${local.day}일';
}
