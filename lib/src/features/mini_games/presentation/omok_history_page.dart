import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/common/error_mapper.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_providers.dart';
import 'package:couple_chat_app/src/features/mini_games/data/omok_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class OmokHistoryPage extends ConsumerWidget {
  const OmokHistoryPage({
    required this.coupleId,
    required this.userId,
    super.key,
  });

  final String coupleId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (coupleId: coupleId, userId: userId);
    final recordAsync = ref.watch(omokRecordProvider(args));
    final gamesAsync = ref.watch(omokAllGamesProvider(args));

    Future<void> refresh() async {
      ref.invalidate(omokRecordProvider(args));
      ref.invalidate(omokAllGamesProvider(args));
      await Future.wait([
        ref.read(omokRecordProvider(args).future),
        ref.read(omokAllGamesProvider(args).future),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('전체 대국 기록'),
        leading: IconButton(
          tooltip: '뒤로가기',
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
      ),
      body: DearBackground(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            key: const ValueKey('omok-all-history-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              recordAsync.when(
                loading: () => const OmokLoadingSkeleton(height: 126),
                error: (error, _) => OmokInlineError(
                  message: '전적을 불러오지 못했어요.\n${toFriendlyErrorMessage(error)}',
                  onRetry: () => ref.invalidate(omokRecordProvider(args)),
                ),
                data: (record) => _RecordSummary(record: record),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '대국 히스토리',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const Spacer(),
                  gamesAsync.valueOrNull == null
                      ? const SizedBox.shrink()
                      : Text(
                          '총 ${gamesAsync.valueOrNull!.length}판',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ],
              ),
              const SizedBox(height: 8),
              gamesAsync.when(
                loading: () => const Column(
                  children: [
                    OmokLoadingSkeleton(height: 76),
                    SizedBox(height: 8),
                    OmokLoadingSkeleton(height: 76),
                    SizedBox(height: 8),
                    OmokLoadingSkeleton(height: 76),
                  ],
                ),
                error: (error, _) => OmokInlineError(
                  message: '기록을 불러오지 못했어요.\n${toFriendlyErrorMessage(error)}',
                  onRetry: () => ref.invalidate(omokAllGamesProvider(args)),
                ),
                data: (games) {
                  if (games.isEmpty) {
                    return const _EmptyHistory();
                  }
                  return DearCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shadowOpacity: 0.35,
                    child: Column(
                      children: [
                        for (var index = 0; index < games.length; index++) ...[
                          OmokHistoryTile(
                            game: games[index],
                            onTap: () => context.push(
                              '/omok/${games[index].sessionId}',
                            ),
                          ),
                          if (index != games.length - 1)
                            Divider(
                              height: 1,
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OmokHistoryTile extends StatelessWidget {
  const OmokHistoryTile({
    required this.game,
    required this.onTap,
    super.key,
  });

  final OmokRecentGame game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final result = omokResultPresentation(context, game.result);
    final date = formatOmokDateTime(game.finishedAt ?? game.createdAt);
    final reason = omokReasonLabel(game.endReason);

    return Semantics(
      button: true,
      label: '${result.label}, $reason, $date, 대국 보기',
      child: ExcludeSemantics(
        child: ListTile(
          key: ValueKey('omok-history-${game.sessionId}'),
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: 10,
          onTap: onTap,
          leading: Container(
            key: ValueKey('omok-result-${game.sessionId}'),
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: result.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: result.border),
            ),
            child: Icon(result.icon, color: result.foreground, size: 21),
          ),
          title: Text(
            result.label,
            style: TextStyle(
              color: result.foreground,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Text('$reason · $date'),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class OmokResultPresentation {
  const OmokResultPresentation({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color border;
}

OmokResultPresentation omokResultPresentation(
  BuildContext context,
  String result,
) {
  final scheme = Theme.of(context).colorScheme;
  switch (result) {
    case 'win':
      return OmokResultPresentation(
        label: '승리',
        icon: Icons.emoji_events_rounded,
        foreground: scheme.onTertiaryContainer,
        background: scheme.tertiaryContainer,
        border: scheme.tertiary,
      );
    case 'loss':
      return OmokResultPresentation(
        label: '패배',
        icon: Icons.close_rounded,
        foreground: scheme.onErrorContainer,
        background: scheme.errorContainer,
        border: scheme.error,
      );
    case 'draw':
      return OmokResultPresentation(
        label: '무승부',
        icon: Icons.balance_rounded,
        foreground: scheme.onSecondaryContainer,
        background: scheme.secondaryContainer,
        border: scheme.outline,
      );
    case 'cancelled':
      return OmokResultPresentation(
        label: '취소',
        icon: Icons.block_rounded,
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHigh,
        border: scheme.outlineVariant,
      );
    default:
      return OmokResultPresentation(
        label: result,
        icon: Icons.info_outline_rounded,
        foreground: scheme.onSurfaceVariant,
        background: scheme.surfaceContainerHigh,
        border: scheme.outlineVariant,
      );
  }
}

String omokReasonLabel(String endReason) {
  switch (endReason) {
    case 'five_in_a_row':
      return '오목 완성';
    case 'timeout':
      return '시간 초과';
    case 'resign':
      return '기권';
    case 'draw':
      return '무승부';
    case 'cancelled':
      return '취소';
    default:
      return endReason;
  }
}

String formatOmokDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final yy = local.year.toString();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final mi = local.minute.toString().padLeft(2, '0');
  return '$yy.$mm.$dd $hh:$mi';
}

class OmokLoadingSkeleton extends StatelessWidget {
  const OmokLoadingSkeleton({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '내용을 불러오는 중',
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(DearRadii.medium),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SkeletonLine(widthFactor: 0.42),
            SizedBox(height: 12),
            _SkeletonLine(widthFactor: 0.82),
            SizedBox(height: 8),
            _SkeletonLine(widthFactor: 0.62),
          ],
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 10,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class OmokInlineError extends StatelessWidget {
  const OmokInlineError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return DearCard(
      shadowOpacity: 0.25,
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

class _RecordSummary extends StatelessWidget {
  const _RecordSummary({required this.record});

  final OmokRecord record;

  @override
  Widget build(BuildContext context) {
    final winRate =
        record.totalGames == 0 ? 0.0 : (record.wins / record.totalGames) * 100;

    return Semantics(
      label:
          '전적 요약, 총 ${record.totalGames}판, ${record.wins}승, ${record.losses}패, ${record.draws}무, 승률 ${winRate.toStringAsFixed(0)}퍼센트',
      child: ExcludeSemantics(
        child: DearCard(
          padding: const EdgeInsets.all(18),
          gradient: DearGradients.softCardFor(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '우리 전적',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                      child: _Metric(label: '승리', value: '${record.wins}')),
                  Expanded(
                      child: _Metric(label: '패배', value: '${record.losses}')),
                  Expanded(
                      child: _Metric(label: '무승부', value: '${record.draws}')),
                  Expanded(
                    child: _Metric(
                      label: '승률',
                      value: '${winRate.toStringAsFixed(0)}%',
                      highlight: true,
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

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: highlight ? scheme.primary : scheme.onSurface,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return DearCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            const Icon(Icons.sports_esports_outlined, size: 34),
            const SizedBox(height: 10),
            const Text('아직 끝난 대국이 없어요.'),
            const SizedBox(height: 4),
            Text(
              '첫 대국을 시작하면 이곳에 기록돼요.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
