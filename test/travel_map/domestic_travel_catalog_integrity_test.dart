import 'package:couple_chat_app/src/features/travel_map/data/domestic_travel_catalog_integrity.dart';
import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('161개 고유 코드와 연속 정렬 순서를 완전한 카탈로그로 판정한다', () {
    final cities = List<TravelCity>.generate(
      expectedDomesticTravelRegionCount,
      (index) => _city(index + 1),
    );

    final result = DomesticTravelCatalogIntegrity.inspect(cities);

    expect(result.isComplete, isTrue);
    expect(result.actualCount, expectedDomesticTravelRegionCount);
  });

  test('운영 응답이 132개면 불완전한 카탈로그로 판정한다', () {
    final cities = List<TravelCity>.generate(132, (index) => _city(index + 1));

    final result = DomesticTravelCatalogIntegrity.inspect(cities);

    expect(result.isComplete, isFalse);
    expect(result.diagnosticSummary, contains('expected=161'));
    expect(result.diagnosticSummary, contains('actual=132'));
  });

  test('중복 코드와 중복·범위 밖 정렬 순서를 함께 보고한다', () {
    final cities = List<TravelCity>.generate(
      expectedDomesticTravelRegionCount,
      (index) => _city(index + 1),
    );
    cities[1] = _city(1);
    cities[2] = _city(999);

    final result = DomesticTravelCatalogIntegrity.inspect(cities);

    expect(result.isComplete, isFalse);
    expect(result.duplicateCodes, contains('SIG_00001'));
    expect(result.duplicateSortOrders, contains(1));
    expect(result.invalidSortOrders, contains(999));
  });
}

TravelCity _city(int sortOrder) {
  final codeNumber = sortOrder.toString().padLeft(5, '0');
  return TravelCity(
    id: 'city-$sortOrder',
    code: 'SIG_$codeNumber',
    name: '지역 $sortOrder',
    regionGroup: '테스트 권역',
    centerLat: 36,
    centerLng: 127,
    sortOrder: sortOrder,
  );
}
