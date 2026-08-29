import 'package:couple_chat_app/src/features/travel_map/presentation/korea_map_label_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('koreaMapScreenFontSize', () {
    test('기본 크기는 11pt이고 Dynamic Type은 지도 안전 범위에서 반영한다', () {
      expect(koreaMapScreenFontSize(TextScaler.noScaling), 11);
      expect(koreaMapScreenFontSize(const TextScaler.linear(0.8)), 10);
      expect(koreaMapScreenFontSize(const TextScaler.linear(2)), 16);
    });
  });

  group('koreaMapLabelDensityForScale', () {
    test('전체·권역·상세 축척 경계를 안정적으로 구분한다', () {
      expect(
        koreaMapLabelDensityForScale(0.625),
        KoreaMapLabelDensity.overview,
      );
      expect(
        koreaMapLabelDensityForScale(0.819),
        KoreaMapLabelDensity.overview,
      );
      expect(
        koreaMapLabelDensityForScale(0.82),
        KoreaMapLabelDensity.regional,
      );
      expect(
        koreaMapLabelDensityForScale(2.149),
        KoreaMapLabelDensity.regional,
      );
      expect(
        koreaMapLabelDensityForScale(2.15),
        KoreaMapLabelDensity.detailed,
      );
    });
  });

  group('koreaMapCanvasFontSize', () {
    test('지도 축소 후에도 화면상 11pt 글자 크기를 유지한다', () {
      const mapScale = 0.625;
      final canvasFontSize = koreaMapCanvasFontSize(
        screenFontSize: 11,
        mapScale: mapScale,
      );

      expect(canvasFontSize, closeTo(17.6, 1e-9));
      expect(canvasFontSize * mapScale, closeTo(11, 1e-9));
    });

    test('지도 확대 후에도 화면상 지정 크기를 유지한다', () {
      const mapScale = 2.4;
      const screenFontSize = 16.0;
      final canvasFontSize = koreaMapCanvasFontSize(
        screenFontSize: screenFontSize,
        mapScale: mapScale,
      );

      expect(canvasFontSize * mapScale, closeTo(screenFontSize, 1e-9));
    });
  });

  group('placeKoreaMapLabel', () {
    const mapRect = Rect.fromLTWH(0, 0, 300, 400);

    test('지역 안에 충분한 공간이 있으면 inline 라벨을 사용한다', () {
      final placement = placeKoreaMapLabel(
        mapRect: mapRect,
        regionBounds: const Rect.fromLTWH(80, 100, 120, 80),
        anchor: const Offset(140, 140),
        inlineSize: const Size(44, 16),
        calloutSize: const Size(56, 24),
        spacing: 4,
        occupiedRects: const [],
      );

      expect(placement.isCallout, isFalse);
      expect(placement.overlapsExisting, isFalse);
      expect(placement.rect.center, const Offset(140, 140));
    });

    test('광명처럼 작은 지역은 글자를 줄이지 않고 외부 callout을 배치한다', () {
      const regionBounds = Rect.fromLTWH(140, 190, 8, 8);
      const anchor = Offset(144, 194);
      final placement = placeKoreaMapLabel(
        mapRect: mapRect,
        regionBounds: regionBounds,
        anchor: anchor,
        inlineSize: const Size(35, 14),
        calloutSize: const Size(44, 22),
        spacing: 4,
        occupiedRects: const [],
      );

      expect(placement.isCallout, isTrue);
      expect(placement.overlapsExisting, isFalse);
      expect(placement.rect.overlaps(regionBounds), isFalse);
      expect(mapRect.contains(placement.rect.topLeft), isTrue);
      expect(mapRect.contains(placement.rect.bottomRight), isTrue);
      expect(
        placement.leaderEndFor(anchor),
        Offset(anchor.dx, placement.rect.bottom),
      );
    });

    test('기존 라벨과 겹치는 inline 후보는 비어 있는 callout 위치로 옮긴다', () {
      const occupied = Rect.fromLTWH(118, 132, 44, 16);
      final placement = placeKoreaMapLabel(
        mapRect: mapRect,
        regionBounds: const Rect.fromLTWH(80, 100, 120, 80),
        anchor: const Offset(140, 140),
        inlineSize: const Size(44, 16),
        calloutSize: const Size(56, 24),
        spacing: 4,
        occupiedRects: const [occupied],
      );

      expect(placement.isCallout, isTrue);
      expect(placement.overlapsExisting, isFalse);
      expect(placement.rect.overlaps(occupied), isFalse);
    });

    test('지도 가장자리의 callout은 화면 밖으로 잘리지 않는다', () {
      final placement = placeKoreaMapLabel(
        mapRect: mapRect,
        regionBounds: const Rect.fromLTWH(1, 1, 8, 8),
        anchor: const Offset(5, 5),
        inlineSize: const Size(40, 14),
        calloutSize: const Size(60, 24),
        spacing: 4,
        occupiedRects: const [],
        forceCallout: true,
      );

      expect(placement.isCallout, isTrue);
      expect(placement.rect.left, greaterThanOrEqualTo(mapRect.left));
      expect(placement.rect.top, greaterThanOrEqualTo(mapRect.top));
      expect(placement.rect.right, lessThanOrEqualTo(mapRect.right));
      expect(placement.rect.bottom, lessThanOrEqualTo(mapRect.bottom));
    });

    test('모든 후보가 겹치면 최소 겹침 후보임을 명시한다', () {
      final placement = placeKoreaMapLabel(
        mapRect: mapRect,
        regionBounds: const Rect.fromLTWH(140, 190, 8, 8),
        anchor: const Offset(144, 194),
        inlineSize: const Size(35, 14),
        calloutSize: const Size(44, 22),
        spacing: 4,
        occupiedRects: const [mapRect],
      );

      expect(placement.isCallout, isTrue);
      expect(placement.overlapsExisting, isTrue);
    });
  });
}
