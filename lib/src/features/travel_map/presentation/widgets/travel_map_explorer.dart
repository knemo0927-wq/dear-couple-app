import 'package:couple_chat_app/src/common/dear_design.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/travel_map_filter.dart';
import 'package:flutter/material.dart';

Future<String?> showTravelPlaceExplorer({
  required BuildContext context,
  required List<TravelMapPlaceItem> places,
  TravelPlaceFilter initialFilter = TravelPlaceFilter.all,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => TravelPlaceExplorerSheet(
      places: places,
      initialFilter: initialFilter,
    ),
  );
}

Future<void> showTravelMapHelp(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '여행 지도 사용법',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: DearColors.ink,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 16),
          const _HelpRow(
            icon: Icons.touch_app_rounded,
            text: '지도나 장소 목록에서 지역을 선택해요.',
          ),
          const _HelpRow(
            icon: Icons.edit_location_alt_rounded,
            text: '색상, 방문일, 메모와 사진을 한 번에 기록해요.',
          ),
          const _HelpRow(
            icon: Icons.search_rounded,
            text: '검색에서 방문·미방문 장소를 빠르게 찾아요.',
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ),
        ],
      ),
    ),
  );
}

class TravelMapSearchLauncher extends StatelessWidget {
  const TravelMapSearchLauncher({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '여행 장소 검색과 방문 필터 열기',
      child: Material(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        shadowColor: DearColors.shadow.withValues(alpha: 0.16),
        child: InkWell(
          key: const ValueKey('travel-map-search-launcher'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DearColors.line),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: DearColors.secondary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '장소 검색',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: DearColors.disabled,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const Icon(
                  Icons.tune_rounded,
                  color: DearColors.coralText,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TravelPlaceExplorerSheet extends StatefulWidget {
  const TravelPlaceExplorerSheet({
    required this.places,
    this.initialFilter = TravelPlaceFilter.all,
    super.key,
  });

  final List<TravelMapPlaceItem> places;
  final TravelPlaceFilter initialFilter;

  @override
  State<TravelPlaceExplorerSheet> createState() =>
      _TravelPlaceExplorerSheetState();
}

class _TravelPlaceExplorerSheetState extends State<TravelPlaceExplorerSheet> {
  late final TextEditingController _searchController;
  late TravelPlaceFilter _filter;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_onSearchChanged);
    _filter = widget.initialFilter;
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final results = filterTravelPlaces(
      places: widget.places,
      query: _searchController.text,
      filter: _filter,
    );
    final showRecent = _filter == TravelPlaceFilter.all &&
        _searchController.text.trim().isEmpty;
    final recent = showRecent
        ? recentVisitedPlaces(widget.places)
        : const <TravelMapPlaceItem>[];
    final maxHeight = MediaQuery.sizeOf(context).height * 0.84;

    return Container(
      height: maxHeight,
      decoration: const BoxDecoration(
        color: DearColors.backgroundTop,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: DearColors.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '여행 장소 찾기',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: DearColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const ValueKey('travel-place-search-field'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '지역이나 국가를 검색해요',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색어 지우기',
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.cancel_rounded),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: DearColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: DearColors.line),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: TravelPlaceFilter.values.map((filter) {
                  final selected = _filter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: ValueKey('travel-filter-${filter.name}'),
                      label: Text(filter.label),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = filter),
                      showCheckmark: true,
                      visualDensity: const VisualDensity(vertical: 1),
                    ),
                  );
                }).toList(growable: false),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? _EmptySearchResult(
                      onReset: () {
                        _searchController.clear();
                        setState(() => _filter = TravelPlaceFilter.all);
                      },
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      children: [
                        if (recent.isNotEmpty) ...[
                          const _SectionLabel(label: '최근 여행'),
                          ...recent.map(_placeTile),
                          const SizedBox(height: 12),
                        ],
                        _SectionLabel(
                          label:
                              showRecent ? '전체 장소' : '검색 결과 ${results.length}개',
                        ),
                        ...results.map(_placeTile),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeTile(TravelMapPlaceItem place) {
    return Semantics(
      button: true,
      label:
          '${place.title}, ${place.subtitle}, ${place.visited ? '방문함' : '미방문'}',
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DearColors.line),
        ),
        child: ListTile(
          key: ValueKey('travel-place-${place.id}'),
          minTileHeight: 56,
          onTap: () => Navigator.of(context).pop(place.id),
          leading: Icon(
            place.visited
                ? Icons.check_circle_rounded
                : Icons.location_on_outlined,
            color: place.visited ? DearColors.coralText : DearColors.muted,
          ),
          title: Text(
            place.title,
            style: const TextStyle(
              color: DearColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(place.subtitle),
          trailing: Text(
            place.visited ? '방문' : '미방문',
            style: TextStyle(
              color:
                  place.visited ? DearColors.coralText : DearColors.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: DearColors.ink,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  const _EmptySearchResult({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.travel_explore_rounded,
              size: 48,
              color: DearColors.muted,
            ),
            const SizedBox(height: 12),
            const Text('조건에 맞는 장소가 없어요.'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onReset,
              child: const Text('필터 초기화'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: DearColors.coralText),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
