import 'dart:async';

import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/auth/data/auth_providers.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_providers.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_repository.dart';
import 'package:couple_chat_app/src/features/mini_games/presentation/omok_history_page.dart';
import 'package:couple_chat_app/src/features/mini_games/presentation/omok_rules_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _MiniGameMenuAction { history, rules, refresh }

class MiniGamesPage extends ConsumerStatefulWidget {
  const MiniGamesPage({super.key});

  @override
  ConsumerState<MiniGamesPage> createState() => _MiniGamesPageState();
}

class _MiniGamesPageState extends ConsumerState<MiniGamesPage> {
  bool _creating = false;
  final Set<int> _shownNotificationIds = <int>{};
  final Set<String> _expirySyncInviteIds = <String>{};

  void _openHistory({required String coupleId, required String userId}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OmokHistoryPage(
          coupleId: coupleId,
          userId: userId,
        ),
      ),
    );
  }

  void _refreshDashboard({String? coupleId, String? userId}) {
    ref.invalidate(myProfileProvider);
    if (coupleId == null || userId == null) return;
    ref.invalidate(latestOutgoingOmokInviteProvider(userId));
    ref.invalidate(omokRecordProvider((coupleId: coupleId, userId: userId)));
    ref.invalidate(
      omokRecentGamesProvider(
        (coupleId: coupleId, userId: userId, limit: 10),
      ),
    );
  }

  Future<void> _createPushInvite() async {
    setState(() => _creating = true);
    try {
      final invite = await ref.read(createOmokPushInviteProvider)();
      if (!mounted) return;
      context.push('/omok-wait/${invite.inviteId}?mode=push');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toFriendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _expireInviteOnce(String inviteId) {
    if (!_expirySyncInviteIds.add(inviteId)) return;
    unawaited(_syncInviteExpiry(inviteId));
  }

  Future<void> _syncInviteExpiry(String inviteId) async {
    try {
      await ref.read(expireOmokInviteProvider)(inviteId);
    } catch (_) {
      _expirySyncInviteIds.remove(inviteId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profileAsync = ref.watch(myProfileProvider);
    final profile = profileAsync.valueOrNull;
    final canOpenHistory =
        profile?.isPaired == true && profile?.coupleId != null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          tooltip: '뒤로가기',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/chat-list');
          },
        ),
        title: const Text('오목'),
        actions: [
          PopupMenuButton<_MiniGameMenuAction>(
            key: const ValueKey('omok-main-overflow'),
            tooltip: '더보기',
            onSelected: (action) {
              switch (action) {
                case _MiniGameMenuAction.history:
                  if (canOpenHistory) {
                    _openHistory(
                      coupleId: profile!.coupleId!,
                      userId: profile.userId,
                    );
                  }
                case _MiniGameMenuAction.rules:
                  showOmokRulesSheet(context);
                case _MiniGameMenuAction.refresh:
                  _refreshDashboard(
                    coupleId: profile?.coupleId,
                    userId: profile?.userId,
                  );
              }
            },
            itemBuilder: (context) => [
              if (canOpenHistory)
                const PopupMenuItem(
                  value: _MiniGameMenuAction.history,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.history_rounded),
                    title: Text('전체 대국 기록'),
                  ),
                ),
              const PopupMenuItem(
                value: _MiniGameMenuAction.rules,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.menu_book_rounded),
                  title: Text('오목 규칙'),
                ),
              ),
              const PopupMenuItem(
                value: _MiniGameMenuAction.refresh,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh_rounded),
                  title: Text('새로고침'),
                ),
              ),
            ],
            icon: const Icon(Icons.more_horiz_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: DearBackground(
        child: profileAsync.when(
          loading: () => const _OmokDashboardSkeleton(),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: OmokInlineError(
                message: '오목 정보를 불러오지 못했어요.\n${toFriendlyErrorMessage(error)}',
                onRetry: () => ref.invalidate(myProfileProvider),
              ),
            ),
          ),
          data: (profile) {
            if (profile == null ||
                !profile.isPaired ||
                profile.coupleId == null) {
              return const Center(child: Text('커플 연결 후 사용할 수 있어요.'));
            }

            final recordArgs = (
              coupleId: profile.coupleId!,
              userId: profile.userId,
            );
            final recentArgs = (
              coupleId: profile.coupleId!,
              userId: profile.userId,
              limit: 10,
            );

            final recordAsync = ref.watch(omokRecordProvider(recordArgs));
            final recentGamesAsync =
                ref.watch(omokRecentGamesProvider(recentArgs));
            final outgoingInviteAsync =
                ref.watch(latestOutgoingOmokInviteProvider(profile.userId));
            final outgoingInvite = outgoingInviteAsync.valueOrNull;
            final hasPendingInvite = outgoingInvite?.isPending ?? false;

            if (outgoingInvite != null &&
                outgoingInvite.status == 'open' &&
                outgoingInvite.isExpired) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _expireInviteOnce(outgoingInvite.id);
              });
            }

            ref.listen<AsyncValue<DateTime?>>(
              latestOmokActivityAtProvider(profile.coupleId!),
              (previous, next) {
                final prevAt = previous?.valueOrNull;
                final nextAt = next.valueOrNull;
                if (nextAt == null || nextAt == prevAt) return;

                ref.invalidate(omokRecordProvider(recordArgs));
                ref.invalidate(omokRecentGamesProvider(recentArgs));
              },
            );

            ref.listen<AsyncValue<List<OmokNotification>>>(
              rematchNotificationsProvider(profile.userId),
              (previous, next) {
                final data = next.valueOrNull;
                if (!mounted || data == null) return;

                final newUnread = data
                    .where((n) =>
                        n.isUnread && !_shownNotificationIds.contains(n.id))
                    .toList(growable: false);
                if (newUnread.isEmpty) return;

                final latest = newUnread.last;
                _shownNotificationIds.addAll(newUnread.map((e) => e.id));

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('상대가 재대결을 만들었어요! 바로 입장해 보세요.'),
                    action: SnackBarAction(
                      label: '입장',
                      onPressed: () =>
                          context.push('/omok/${latest.sessionId}'),
                    ),
                  ),
                );

                unawaited(ref.read(markOmokNotificationsReadProvider)(
                    newUnread.map((e) => e.id).toList()));
              },
            );

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                DearCard(
                  padding: const EdgeInsets.all(18),
                  radius: DearRadii.large,
                  gradient: DearGradients.softCardFor(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          DearIconBubble(
                            icon: Icons.sports_esports_rounded,
                            size: 56,
                            background: scheme.surface,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '한 판 신청하기',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '우리, 지금 한 판 어때요?',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      outgoingInviteAsync.when(
                        loading: () => const _MiniSkeletonLines(rows: 1),
                        error: (error, _) => _CompactLoadError(
                          message: '최근 초대 상태를 확인하지 못했어요.',
                          onRetry: () => ref.invalidate(
                            latestOutgoingOmokInviteProvider(profile.userId),
                          ),
                        ),
                        data: (invite) => invite == null
                            ? const SizedBox.shrink()
                            : _LatestInviteStatus(
                                invite: invite,
                                actionLabel: invite.isPending
                                    ? '대기실 보기'
                                    : invite.isUsed
                                        ? '대국 보기'
                                        : null,
                                onAction: invite.isPending
                                    ? () => context.push(
                                          '/omok-wait/${invite.id}?mode=push',
                                        )
                                    : invite.isUsed
                                        ? () => context.push(
                                              '/omok/${invite.sessionId}',
                                            )
                                        : null,
                              ),
                      ),
                      const SizedBox(height: 12),
                      DearGradientButton(
                        onPressed: _creating || hasPendingInvite
                            ? null
                            : _createPushInvite,
                        label: _creating
                            ? '신청 중...'
                            : hasPendingInvite
                                ? '상대 응답 대기 중'
                                : '신청하기',
                        icon: Icons.notifications_active_rounded,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DearCard(
                  padding: const EdgeInsets.all(18),
                  shadowOpacity: 0.45,
                  child: recordAsync.when(
                    loading: () => const _MiniSkeletonLines(),
                    error: (error, _) => _CompactLoadError(
                      message: '전적을 불러오지 못했어요.',
                      onRetry: () =>
                          ref.invalidate(omokRecordProvider(recordArgs)),
                    ),
                    data: (record) {
                      final winRate = record.totalGames == 0
                          ? 0.0
                          : (record.wins / record.totalGames) * 100;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const DearIconBubble(
                                      icon: Icons.bar_chart_rounded,
                                      size: 34,
                                      iconSize: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        '우리 기록',
                                        maxLines: 2,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: scheme.onSurface,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                key: const ValueKey(
                                  'omok-record-history-button',
                                ),
                                onPressed: () => _openHistory(
                                  coupleId: profile.coupleId!,
                                  userId: profile.userId,
                                ),
                                label: const Text('전체 전적'),
                                iconAlignment: IconAlignment.end,
                                icon: const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: scheme.onSurfaceVariant,
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _recordTile(
                                  context,
                                  '승리',
                                  '${record.wins}',
                                ),
                              ),
                              Expanded(
                                child: _recordTile(
                                  context,
                                  '패배',
                                  '${record.losses}',
                                ),
                              ),
                              Expanded(
                                child: _recordTile(
                                  context,
                                  '승률',
                                  '${winRate.toStringAsFixed(0)}%',
                                  highlight: true,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                DearCard(
                  padding: const EdgeInsets.all(18),
                  shadowOpacity: 0.45,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '최근 경기',
                              maxLines: 2,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                          ),
                          TextButton.icon(
                            key: const ValueKey(
                              'omok-recent-history-button',
                            ),
                            onPressed: () => _openHistory(
                              coupleId: profile.coupleId!,
                              userId: profile.userId,
                            ),
                            label: const Text('더보기'),
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.onSurfaceVariant,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      recentGamesAsync.when(
                        loading: () => const _MiniSkeletonLines(rows: 3),
                        error: (error, _) => _CompactLoadError(
                          message: '최근 대국을 불러오지 못했어요.',
                          onRetry: () => ref.invalidate(
                            omokRecentGamesProvider(recentArgs),
                          ),
                        ),
                        data: (games) {
                          if (games.isEmpty) {
                            return const Text('아직 끝난 대국이 없어요.');
                          }
                          return Column(
                            children: games.map((game) {
                              return OmokHistoryTile(
                                game: game,
                                onTap: () =>
                                    context.push('/omok/${game.sessionId}'),
                              );
                            }).toList(growable: false),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _recordTile(
    BuildContext context,
    String label,
    String value, {
    bool highlight = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            color: highlight ? scheme.primary : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LatestInviteStatus extends StatelessWidget {
  const _LatestInviteStatus({
    required this.invite,
    required this.actionLabel,
    required this.onAction,
  });

  final OmokInviteState invite;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expired = invite.isExpired;
    final accepted = invite.isUsed;
    final rejected = invite.isRejected;
    final (icon, label, color) = accepted
        ? (
            Icons.check_circle_rounded,
            '상대가 초대를 수락했어요.',
            scheme.onTertiaryContainer,
          )
        : rejected
            ? (
                Icons.person_off_rounded,
                '상대가 이번 초대를 거절했어요.',
                scheme.onSurfaceVariant,
              )
            : expired
                ? (
                    Icons.timer_off_rounded,
                    '초대가 만료됐어요. 다시 보내 주세요.',
                    scheme.error,
                  )
                : (
                    Icons.schedule_rounded,
                    '전송 완료 · 상대 응답 대기 중',
                    scheme.primary,
                  );

    return Semantics(
      liveRegion: true,
      label: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (invite.isPending || onAction != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (invite.isPending)
                    Expanded(
                      child: Text(
                        '${formatOmokDateTime(invite.expiresAt)}까지',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (onAction != null && actionLabel != null)
                    TextButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniSkeletonLines extends StatelessWidget {
  const _MiniSkeletonLines({this.rows = 2});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '내용을 불러오는 중',
      child: Column(
        children: List.generate(
          rows,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: index == rows - 1 ? 0 : 10),
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactLoadError extends StatelessWidget {
  const _CompactLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_off_rounded, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    );
  }
}

class _OmokDashboardSkeleton extends StatelessWidget {
  const _OmokDashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: const [
        OmokLoadingSkeleton(height: 180),
        SizedBox(height: 12),
        OmokLoadingSkeleton(height: 132),
        SizedBox(height: 12),
        OmokLoadingSkeleton(height: 210),
      ],
    );
  }
}

class OmokInviteWaitPage extends ConsumerStatefulWidget {
  const OmokInviteWaitPage({
    required this.inviteId,
    this.mode,
    super.key,
  });

  final String inviteId;
  final String? mode;

  @override
  ConsumerState<OmokInviteWaitPage> createState() => _OmokInviteWaitPageState();
}

class _OmokInviteWaitPageState extends ConsumerState<OmokInviteWaitPage> {
  bool _navigated = false;
  bool _expirySyncRequested = false;
  late Stream<OmokInviteState?> _inviteStream;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  Object? _expirySyncError;

  @override
  void initState() {
    super.initState();
    _inviteStream = ref.read(watchOmokInviteProvider)(widget.inviteId);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _inviteStream = ref.read(watchOmokInviteProvider)(widget.inviteId);
      _now = DateTime.now();
    });
  }

  Future<void> _syncExpiry() async {
    if (_expirySyncRequested) return;
    setState(() {
      _expirySyncRequested = true;
      _expirySyncError = null;
    });
    try {
      await ref.read(expireOmokInviteProvider)(widget.inviteId);
    } catch (error) {
      if (mounted) setState(() => _expirySyncError = error);
    }
  }

  void _retryExpirySync() {
    setState(() => _expirySyncRequested = false);
    unawaited(_syncExpiry());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('오목 대기실')),
      body: StreamBuilder<OmokInviteState?>(
        stream: _inviteStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: OmokLoadingSkeleton(height: 220)),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: OmokInlineError(
                  message:
                      '대기실 연결을 확인하고 있어요.\n${toFriendlyErrorMessage(snapshot.error!)}',
                  onRetry: _retry,
                ),
              ),
            );
          }

          final invite = snapshot.data;
          if (invite == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: OmokInlineError(
                  message: '초대 정보를 찾을 수 없어요.',
                  onRetry: _retry,
                ),
              ),
            );
          }

          if (invite.isUsed && !_navigated) {
            _navigated = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final sessionId = invite.sessionId;
              if (!mounted || sessionId == null) return;
              context.go('/omok/$sessionId');
            });
          }

          final expired =
              invite.status == 'expired' || !_now.isBefore(invite.expiresAt);
          final rejected = invite.isRejected;
          final accepted = invite.isUsed;
          if (expired && invite.status == 'open' && !_expirySyncRequested) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_syncExpiry());
            });
          }
          final remaining = invite.expiresAt.difference(_now);
          final remainingSeconds = remaining.inSeconds.clamp(0, 3599);
          final remainingLabel =
              '${remainingSeconds ~/ 60}분 ${(remainingSeconds % 60).toString().padLeft(2, '0')}초';
          final title = accepted
              ? '상대가 초대를 수락했어요'
              : rejected
                  ? '상대가 초대를 거절했어요'
                  : expired
                      ? '초대가 만료됐어요'
                      : '상대 응답을 기다리고 있어요';
          final icon = accepted
              ? Icons.check_circle_rounded
              : rejected
                  ? Icons.person_off_rounded
                  : expired
                      ? Icons.timer_off_rounded
                      : Icons.notifications_active_rounded;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Semantics(
                liveRegion: true,
                label: title,
                child: DearCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!accepted && !rejected && !expired)
                        const SizedBox(
                          width: 54,
                          height: 54,
                          child: CircularProgressIndicator(strokeWidth: 4),
                        )
                      else
                        Icon(icon, size: 56, color: scheme.primary),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 12),
                      if (!accepted && !rejected && !expired) ...[
                        Text(
                          widget.mode == 'push'
                              ? '상대에게 오목 초대 알림을 보냈어요.'
                              : '초대를 수락하면 대국이 자동으로 시작돼요.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '만료까지 $remainingLabel',
                          key: const ValueKey('omok-invite-countdown'),
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.wifi_rounded,
                              size: 17,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '실시간으로 상대 응답 확인 중',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ] else if (accepted)
                        const Text('대국 화면으로 이동하고 있어요.')
                      else ...[
                        Text(
                          expired
                              ? '응답 시간이 지났어요. 새 초대를 보내 수 있어요.'
                              : '다음에 다시 초대해 보세요.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => context.go('/mini-games'),
                            icon: const Icon(Icons.replay_rounded),
                            label: const Text('새 초대 보내기'),
                          ),
                        ),
                        if (_expirySyncError != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _retryExpirySync,
                            icon: const Icon(Icons.sync_rounded, size: 18),
                            label: const Text('만료 상태 다시 확인'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class OmokInviteAcceptPage extends ConsumerStatefulWidget {
  const OmokInviteAcceptPage({
    required this.inviteId,
    super.key,
  });

  final String inviteId;

  @override
  ConsumerState<OmokInviteAcceptPage> createState() =>
      _OmokInviteAcceptPageState();
}

class _OmokInviteAcceptPageState extends ConsumerState<OmokInviteAcceptPage> {
  bool _accepting = false;
  bool _rejecting = false;
  bool _expirySyncRequested = false;
  late Stream<OmokInviteState?> _inviteStream;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  Object? _actionError;

  @override
  void initState() {
    super.initState();
    _inviteStream = ref.read(watchOmokInviteProvider)(widget.inviteId);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _retryStream() {
    setState(() {
      _inviteStream = ref.read(watchOmokInviteProvider)(widget.inviteId);
      _actionError = null;
      _now = DateTime.now();
    });
  }

  Future<void> _accept() async {
    if (_accepting || _rejecting) return;
    setState(() {
      _accepting = true;
      _actionError = null;
    });
    try {
      final sessionId =
          await ref.read(acceptOmokPushInviteProvider)(widget.inviteId);
      if (!mounted) return;
      context.go('/omok/$sessionId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = e);
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _reject() async {
    if (_rejecting || _accepting) return;
    setState(() {
      _rejecting = true;
      _actionError = null;
    });
    try {
      await ref.read(rejectOmokPushInviteProvider)(widget.inviteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오목 초대를 거절했어요.')),
      );
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) setState(() => _rejecting = false);
    }
  }

  Future<void> _syncExpiry() async {
    if (_expirySyncRequested) return;
    _expirySyncRequested = true;
    try {
      await ref.read(expireOmokInviteProvider)(widget.inviteId);
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('오목 초대'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          tooltip: '뒤로가기',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/mini-games');
          },
        ),
      ),
      body: DearBackground(
        child: StreamBuilder<OmokInviteState?>(
          stream: _inviteStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: OmokLoadingSkeleton(height: 300)),
              );
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: OmokInlineError(
                    message:
                        '초대 상태를 불러오지 못했어요.\n${toFriendlyErrorMessage(snapshot.error!)}',
                    onRetry: _retryStream,
                  ),
                ),
              );
            }

            final invite = snapshot.data;
            if (invite == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: OmokInlineError(
                    message: '초대 정보를 찾을 수 없어요.',
                    onRetry: _retryStream,
                  ),
                ),
              );
            }

            final expired =
                invite.status == 'expired' || !_now.isBefore(invite.expiresAt);
            final rejected = invite.isRejected;
            final accepted = invite.isUsed;
            final pending = invite.status == 'open' && !expired;
            if (expired && invite.status == 'open' && !_expirySyncRequested) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_syncExpiry());
              });
            }

            final (icon, title, description) = accepted
                ? (
                    Icons.check_circle_rounded,
                    '이미 수락한 초대예요',
                    '시작된 대국으로 이동할 수 있어요.',
                  )
                : rejected
                    ? (
                        Icons.person_off_rounded,
                        '초대를 거절했어요',
                        '이 초대로는 대국이 시작되지 않아요.',
                      )
                    : expired
                        ? (
                            Icons.timer_off_rounded,
                            '초대가 만료됐어요',
                            '응답 시간이 지나 수락할 수 없어요.',
                          )
                        : (
                            Icons.sports_esports_rounded,
                            '오목 한 판, 함께할까요?',
                            '${formatOmokDateTime(invite.expiresAt)}까지 응답할 수 있어요.',
                          );

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Semantics(
                  liveRegion: true,
                  label: title,
                  child: DearCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DearIconBubble(icon: icon, size: 64, iconSize: 30),
                        const SizedBox(height: 18),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w900,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          description,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        if (_actionError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            toFriendlyErrorMessage(_actionError!),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.error),
                          ),
                        ],
                        const SizedBox(height: 22),
                        if (pending)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  key: const ValueKey(
                                    'omok-invite-reject-button',
                                  ),
                                  onPressed:
                                      _rejecting || _accepting ? null : _reject,
                                  child: Text(_rejecting ? '거절 중...' : '거절'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: FilledButton(
                                  key: const ValueKey(
                                    'omok-invite-accept-button',
                                  ),
                                  onPressed:
                                      _accepting || _rejecting ? null : _accept,
                                  child: Text(
                                    _accepting ? '수락 중...' : '수락하고 시작',
                                  ),
                                ),
                              ),
                            ],
                          )
                        else if (accepted && invite.sessionId != null)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  context.go('/omok/${invite.sessionId}'),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('대국으로 이동'),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => context.go('/mini-games'),
                              child: const Text('오목으로 돌아가기'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
