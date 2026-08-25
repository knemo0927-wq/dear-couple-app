import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:flutter/material.dart';

enum TravelMapSection { korea, world }

enum TravelMapMenuAction { all, visited, unvisited, help }

class TravelMapTopBar extends StatelessWidget implements PreferredSizeWidget {
  const TravelMapTopBar({
    required this.section,
    required this.onBack,
    required this.onSectionSelected,
    required this.onMenuSelected,
    super.key,
  });

  final TravelMapSection section;
  final VoidCallback onBack;
  final ValueChanged<TravelMapSection> onSectionSelected;
  final ValueChanged<TravelMapMenuAction> onMenuSelected;

  @override
  Size get preferredSize => const Size.fromHeight(124);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white.withValues(alpha: 0.94),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 60,
      leadingWidth: 60,
      leading: IconButton(
        tooltip: '뒤로가기',
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
      ),
      centerTitle: true,
      title: Text(
        '여행 지도',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: DearColors.ink,
              fontWeight: FontWeight.w900,
            ),
      ),
      actions: [
        PopupMenuButton<TravelMapMenuAction>(
          key: const ValueKey('travel-map-overflow'),
          tooltip: '여행 지도 더보기',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: onMenuSelected,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: TravelMapMenuAction.all,
              height: 48,
              child: _MenuLabel(
                icon: Icons.list_alt_rounded,
                label: '전체 장소 보기',
              ),
            ),
            PopupMenuItem(
              value: TravelMapMenuAction.visited,
              height: 48,
              child: _MenuLabel(
                icon: Icons.check_circle_outline_rounded,
                label: '방문한 곳 보기',
              ),
            ),
            PopupMenuItem(
              value: TravelMapMenuAction.unvisited,
              height: 48,
              child: _MenuLabel(
                icon: Icons.add_location_alt_outlined,
                label: '미방문 장소 보기',
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: TravelMapMenuAction.help,
              height: 48,
              child: _MenuLabel(
                icon: Icons.help_outline_rounded,
                label: '지도 사용법',
              ),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: TravelMapSegments(
            section: section,
            onSelected: onSectionSelected,
          ),
        ),
      ),
    );
  }
}

class TravelMapSegments extends StatelessWidget {
  const TravelMapSegments({
    required this.section,
    required this.onSelected,
    super.key,
  });

  final TravelMapSection section;
  final ValueChanged<TravelMapSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '국내와 세계 여행 지도 선택',
      child: Container(
        height: 54,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: DearColors.blushDeep,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DearColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: _TravelMapSegment(
                key: const ValueKey('travel-map-segment-korea'),
                label: '국내',
                selected: section == TravelMapSection.korea,
                onTap: section == TravelMapSection.korea
                    ? null
                    : () => onSelected(TravelMapSection.korea),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _TravelMapSegment(
                key: const ValueKey('travel-map-segment-world'),
                label: '세계',
                selected: section == TravelMapSection.world,
                onTap: section == TravelMapSection.world
                    ? null
                    : () => onSelected(TravelMapSection.world),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelMapSegment extends StatelessWidget {
  const _TravelMapSegment({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: '$label 여행 지도',
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        elevation: selected ? 1 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox.expand(
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected
                          ? DearColors.coralText
                          : DearColors.secondary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 21, color: DearColors.secondary),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
