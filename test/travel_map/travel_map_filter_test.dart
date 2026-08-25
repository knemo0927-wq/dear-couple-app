import 'package:couple_chat_app/src/features/travel_map/data/map_query_scope.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/travel_map_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('coupleScopedMapQuery', () {
    test('커플 ID를 정규화해 서버 필터 명세로 만든다', () {
      final scope = coupleScopedMapQuery('  couple-1  ');

      expect(CoupleScopedMapQuery.column, 'couple_id');
      expect(scope.value, 'couple-1');
    });

    test('빈 커플 ID로 범위 없는 쿼리를 만들 수 없다', () {
      expect(() => coupleScopedMapQuery('   '), throwsArgumentError);
    });
  });

  group('travel map filters', () {
    final places = <TravelMapPlaceItem>[
      TravelMapPlaceItem(
        id: 'seoul',
        title: '서울',
        subtitle: '대한민국 · 수도권',
        visited: true,
        updatedAt: DateTime(2026, 7, 10),
      ),
      const TravelMapPlaceItem(
        id: 'busan',
        title: '부산',
        subtitle: '대한민국 · 영남',
        visited: false,
      ),
      TravelMapPlaceItem(
        id: 'jp',
        title: '일본',
        subtitle: 'Japan',
        visited: true,
        updatedAt: DateTime(2026, 7, 11),
      ),
    ];

    test('방문 및 미방문 상태를 색상과 무관하게 필터링한다', () {
      final visited = filterTravelPlaces(
        places: places,
        query: '',
        filter: TravelPlaceFilter.visited,
      );
      final unvisited = filterTravelPlaces(
        places: places,
        query: '',
        filter: TravelPlaceFilter.unvisited,
      );

      expect(visited.map((place) => place.id), containsAll(['seoul', 'jp']));
      expect(unvisited.map((place) => place.id), ['busan']);
    });

    test('한글 제목과 영문 부제 검색을 모두 지원한다', () {
      expect(
        filterTravelPlaces(
          places: places,
          query: '서울',
          filter: TravelPlaceFilter.all,
        ).single.id,
        'seoul',
      );
      expect(
        filterTravelPlaces(
          places: places,
          query: 'jApAn',
          filter: TravelPlaceFilter.all,
        ).single.id,
        'jp',
      );
    });

    test('최근 여행은 방문 기록 갱신 시각 역순이다', () {
      expect(
        recentVisitedPlaces(places).map((place) => place.id),
        ['jp', 'seoul'],
      );
    });
  });
}
