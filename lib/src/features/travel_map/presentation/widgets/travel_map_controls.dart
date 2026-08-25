import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:flutter/material.dart';

class TravelMapProgressCard extends StatelessWidget {
  const TravelMapProgressCard({
    required this.visitedCount,
    required this.totalCount,
    required this.placeLabel,
    super.key,
  });

  final int visitedCount;
  final int totalCount;
  final String placeLabel;

  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : visitedCount / totalCount;
    final percent = (progress * 100).round();
    return Semantics(
      container: true,
      label:
          '$placeLabel 여행 지도 방문 상태. 전체 $totalCount곳 중 $visitedCount곳 방문, 방문률 $percent퍼센트.',
      child: Container(
        width: 154,
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: DearColors.line),
          boxShadow: dearSoftShadow(0.7),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '방문률',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: DearColors.ink,
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
                        color: DearColors.coralText,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                ),
                const Spacer(),
                Text(
                  '$visitedCount/$totalCount',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: DearColors.secondary,
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
                backgroundColor: DearColors.blushDeep,
                color: DearColors.coral,
              ),
            ),
          ],
        ),
      ),
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
    super.key,
  });

  final bool canZoomIn;
  final bool canZoomOut;
  final bool locating;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCurrentLocation;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: DearColors.line),
          boxShadow: dearSoftShadow(0.65),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MapControlButton(
              tooltip: locating ? '현재 위치 찾는 중' : '현재 위치',
              icon: Icons.my_location_rounded,
              loading: locating,
              onPressed: locating ? null : onCurrentLocation,
            ),
            const _ControlDivider(),
            _MapControlButton(
              tooltip: '확대',
              icon: Icons.add_rounded,
              onPressed: canZoomIn ? onZoomIn : null,
            ),
            const _ControlDivider(),
            _MapControlButton(
              tooltip: '축소',
              icon: Icons.remove_rounded,
              onPressed: canZoomOut ? onZoomOut : null,
            ),
            const _ControlDivider(),
            _MapControlButton(
              tooltip: '지도 전체 보기',
              icon: Icons.center_focus_strong_rounded,
              onPressed: onReset,
            ),
          ],
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
      color: DearColors.ink,
      disabledColor: DearColors.disabled,
    );
  }
}

class _ControlDivider extends StatelessWidget {
  const _ControlDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 30,
      child: Divider(height: 1, color: DearColors.line),
    );
  }
}

class TravelMapLoadingState extends StatelessWidget {
  const TravelMapLoadingState({this.label = '여행 지도를 불러오고 있어요', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DearColors.backgroundTop,
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
    return ColoredBox(
      color: DearColors.backgroundTop,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: DearColors.muted,
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
