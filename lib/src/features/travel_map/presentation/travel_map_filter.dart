enum TravelPlaceFilter { all, visited, unvisited }

extension TravelPlaceFilterLabel on TravelPlaceFilter {
  String get label => switch (this) {
        TravelPlaceFilter.all => '전체',
        TravelPlaceFilter.visited => '방문',
        TravelPlaceFilter.unvisited => '미방문',
      };
}

class TravelMapPlaceItem {
  const TravelMapPlaceItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.visited,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool visited;
  final DateTime? updatedAt;
}

List<TravelMapPlaceItem> filterTravelPlaces({
  required Iterable<TravelMapPlaceItem> places,
  required String query,
  required TravelPlaceFilter filter,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final result = places.where((place) {
    final matchesFilter = switch (filter) {
      TravelPlaceFilter.all => true,
      TravelPlaceFilter.visited => place.visited,
      TravelPlaceFilter.unvisited => !place.visited,
    };
    if (!matchesFilter) return false;
    if (normalizedQuery.isEmpty) return true;

    return place.title.toLowerCase().contains(normalizedQuery) ||
        place.subtitle.toLowerCase().contains(normalizedQuery);
  }).toList(growable: false);

  return result
    ..sort((a, b) {
      if (a.visited != b.visited) return a.visited ? -1 : 1;
      return a.title.compareTo(b.title);
    });
}

List<TravelMapPlaceItem> recentVisitedPlaces(
  Iterable<TravelMapPlaceItem> places, {
  int limit = 3,
}) {
  if (limit <= 0) return const <TravelMapPlaceItem>[];

  final result = places.where((place) => place.visited).toList(growable: false)
    ..sort((a, b) {
      final aUpdated = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bUpdated = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final byUpdated = bUpdated.compareTo(aUpdated);
      return byUpdated != 0 ? byUpdated : a.title.compareTo(b.title);
    });
  return result.take(limit).toList(growable: false);
}
