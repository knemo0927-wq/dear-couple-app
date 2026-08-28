import 'package:flutter/material.dart';

class TravelMapProgressCard extends StatelessWidget {
  const TravelMapProgressCard({
    required this.visitedCount,
    required this.totalCount,
    required this.placeLabel,
    this.compact = false,
    this.expanded = false,
    super.key,
  });

  final int visitedCount;
  final int totalCount;
  final String placeLabel;
  final bool compact;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = totalCount == 0 ? 0.0 : visitedCount / totalCount;
    final percent = (progress * 100).round();
    final Widget card;
    if (compact) {
      card = Container(
        key: const ValueKey('travel-map-progress-surface'),
        width: expanded ? double.infinity : 196,
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$placeLabel 방문 $visitedCount/$totalCount',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$percent%',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      );
    } else {
      card = Container(
        key: const ValueKey('travel-map-progress-surface'),
        width: expanded ? double.infinity : 154,
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '방문률',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$percent%',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                ),
                const Spacer(),
                Text(
                  '$visitedCount/$totalCount',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: scheme.surfaceContainerHighest,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      key: const ValueKey('travel-map-progress-card'),
      container: true,
      label:
          '$placeLabel 여행 지도 방문 상태. 전체 $totalCount곳 중 $visitedCount곳 방문, 방문률 $percent퍼센트.',
      child: card,
    );
  }
}

class TravelMapZoomControls extends StatelessWidget {
  const TravelMapZoomControls({
    required this.canZoomIn,
    required this.canZoomOut,
    required this.locating,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCurrentLocation,
    required this.onReset,
    this.horizontal = false,
    super.key,
  });

  final bool canZoomIn;
  final bool canZoomOut;
  final bool locating;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCurrentLocation;
  final VoidCallback onReset;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final buttons = <Widget>[
      _MapControlButton(
        tooltip: locating ? '현재 위치 찾는 중' : '현재 위치',
        icon: Icons.my_location_rounded,
        loading: locating,
        onPressed: locating ? null : onCurrentLocation,
      ),
      _ControlDivider(horizontal: horizontal),
      _MapControlButton(
        tooltip: '확대',
        icon: Icons.add_rounded,
        onPressed: canZoomIn ? onZoomIn : null,
      ),
      _ControlDivider(horizontal: horizontal),
      _MapControlButton(
        tooltip: '축소',
        icon: Icons.remove_rounded,
        onPressed: canZoomOut ? onZoomOut : null,
      ),
      _ControlDivider(horizontal: horizontal),
      _MapControlButton(
        tooltip: '지도 전체 보기',
        icon: Icons.center_focus_strong_rounded,
        onPressed: onReset,
      ),
    ];
    return Material(
      key: const ValueKey('travel-map-zoom-controls'),
      color: scheme.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outline),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: horizontal
            ? Row(mainAxisSize: MainAxisSize.min, children: buttons)
            : Column(mainAxisSize: MainAxisSize.min, children: buttons),
      ),
    );
  }
}

class TravelMapAccessibleOverlay extends StatelessWidget {
  const TravelMapAccessibleOverlay({
    required this.placeListLauncher,
    required this.visitedCount,
    required this.totalCount,
    required this.placeLabel,
    required this.realtimeError,
    required this.realtimeSemanticLabel,
    required this.zoomBottom,
    this.zoomControlsBuilder,
    super.key,
  });

  final Widget placeListLauncher;
  final int visitedCount;
  final int totalCount;
  final String placeLabel;
  final bool realtimeError;
  final String realtimeSemanticLabel;
  final double zoomBottom;
  final Widget Function(bool horizontal)? zoomControlsBuilder;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final landscape = constraints.maxWidth > constraints.maxHeight;
          final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
          final compactProgress =
              landscape || constraints.maxWidth < 360 || largeText;
          final progress = TravelMapProgressCard(
            visitedCount: visitedCount,
            totalCount: totalCount,
            placeLabel: placeLabel,
            compact: compactProgress,
            expanded: compactProgress,
          );
          final realtimeBadge = realtimeError
              ? _TravelMapRealtimeBadge(label: realtimeSemanticLabel)
              : null;
          final zoomBuilder = zoomControlsBuilder;
          final putZoomInTopRow =
              landscape && zoomBuilder != null && constraints.maxWidth >= 640;

          if (landscape) {
            return Stack(
              children: [
                Positioned(
                  left: 16,
                  right: 16,
                  top: 8,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: placeListLauncher),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: (constraints.maxWidth * 0.28)
                            .clamp(160.0, 220.0)
                            .toDouble(),
                        child: progress,
                      ),
                      if (putZoomInTopRow) ...[
                        const SizedBox(width: 12),
                        zoomBuilder(true),
                      ],
                      if (realtimeBadge != null) ...[
                        const SizedBox(width: 12),
                        realtimeBadge,
                      ],
                    ],
                  ),
                ),
                if (zoomBuilder != null && !putZoomInTopRow)
                  Positioned(
                    left: 16,
                    top: compactProgress ? 82 : 70,
                    child: zoomBuilder(true),
                  ),
              ],
            );
          }

          return Stack(
            children: [
              Positioned(
                left: 20,
                right: 20,
                top: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    placeListLauncher,
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (compactProgress)
                          Expanded(child: progress)
                        else
                          progress,
                        if (realtimeBadge != null) ...[
                          const Spacer(),
                          realtimeBadge,
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (zoomBuilder != null)
                Positioned(
                  right: 20,
                  bottom: zoomBottom + (largeText ? 48 : 0),
                  child: zoomBuilder(false),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TravelMapRealtimeBadge extends StatelessWidget {
  const _TravelMapRealtimeBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '실시간 연결이 끊겼어요. 마지막 기록을 표시하고 있어요.',
      child: Semantics(
        key: const ValueKey('travel-map-realtime-error'),
        liveRegion: true,
        label: label,
        child: Material(
          color: scheme.surface,
          shape: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.cloud_off_rounded, color: scheme.error),
          ),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: onPressed,
      icon: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Icon(icon, size: 23),
      color: scheme.onSurface,
      disabledColor: scheme.onSurface.withValues(alpha: 0.38),
    );
  }
}

class _ControlDivider extends StatelessWidget {
  const _ControlDivider({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).colorScheme.outlineVariant;
    return horizontal
        ? SizedBox(
            height: 30,
            child: VerticalDivider(width: 1, color: dividerColor),
          )
        : SizedBox(
            width: 30,
            child: Divider(height: 1, color: dividerColor),
          );
  }
}

class TravelMapLoadingState extends StatelessWidget {
  const TravelMapLoadingState({this.label = '여행 지도를 불러오고 있어요', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Center(
        child: Semantics(
          liveRegion: true,
          label: label,
          child: const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}

class TravelMapErrorState extends StatelessWidget {
  const TravelMapErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
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
