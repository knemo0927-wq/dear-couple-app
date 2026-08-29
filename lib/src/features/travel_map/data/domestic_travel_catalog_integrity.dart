import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';

const int expectedDomesticTravelRegionCount = 161;

class DomesticTravelCatalogIntegrity {
  const DomesticTravelCatalogIntegrity({
    required this.actualCount,
    required this.duplicateCodes,
    required this.duplicateSortOrders,
    required this.invalidCodes,
    required this.invalidSortOrders,
    required this.missingMetadataCount,
  });

  final int actualCount;
  final Set<String> duplicateCodes;
  final Set<int> duplicateSortOrders;
  final Set<String> invalidCodes;
  final Set<int> invalidSortOrders;
  final int missingMetadataCount;

  bool get isComplete =>
      actualCount == expectedDomesticTravelRegionCount &&
      duplicateCodes.isEmpty &&
      duplicateSortOrders.isEmpty &&
      invalidCodes.isEmpty &&
      invalidSortOrders.isEmpty &&
      missingMetadataCount == 0;

  String get diagnosticSummary => [
        'expected=$expectedDomesticTravelRegionCount',
        'actual=$actualCount',
        if (duplicateCodes.isNotEmpty)
          'duplicateCodes=${duplicateCodes.toList()..sort()}',
        if (duplicateSortOrders.isNotEmpty)
          'duplicateSortOrders=${duplicateSortOrders.toList()..sort()}',
        if (invalidCodes.isNotEmpty)
          'invalidCodes=${invalidCodes.toList()..sort()}',
        if (invalidSortOrders.isNotEmpty)
          'invalidSortOrders=${invalidSortOrders.toList()..sort()}',
        if (missingMetadataCount > 0) 'missingMetadata=$missingMetadataCount',
      ].join(', ');

  factory DomesticTravelCatalogIntegrity.inspect(List<TravelCity> cities) {
    final seenCodes = <String>{};
    final duplicateCodes = <String>{};
    final seenSortOrders = <int>{};
    final duplicateSortOrders = <int>{};
    final invalidCodes = <String>{};
    final invalidSortOrders = <int>{};
    var missingMetadataCount = 0;
    final validCode = RegExp(r'^(METRO_\d{2}|SIG_\d{5})$');

    for (final city in cities) {
      final code = city.code.trim();
      if (!seenCodes.add(code)) duplicateCodes.add(code);
      if (!seenSortOrders.add(city.sortOrder)) {
        duplicateSortOrders.add(city.sortOrder);
      }
      if (!validCode.hasMatch(code)) invalidCodes.add(code);
      if (city.sortOrder < 1 ||
          city.sortOrder > expectedDomesticTravelRegionCount) {
        invalidSortOrders.add(city.sortOrder);
      }
      if (city.name.trim().isEmpty || city.regionGroup.trim().isEmpty) {
        missingMetadataCount += 1;
      }
    }

    return DomesticTravelCatalogIntegrity(
      actualCount: cities.length,
      duplicateCodes: duplicateCodes,
      duplicateSortOrders: duplicateSortOrders,
      invalidCodes: invalidCodes,
      invalidSortOrders: invalidSortOrders,
      missingMetadataCount: missingMetadataCount,
    );
  }
}
