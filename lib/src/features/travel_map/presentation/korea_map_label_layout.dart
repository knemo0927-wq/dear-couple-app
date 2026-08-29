import 'dart:math' as math;

import 'package:flutter/material.dart';

enum KoreaMapLabelDensity { overview, regional, detailed }

double koreaMapScreenFontSize(TextScaler textScaler) =>
    textScaler.scale(11).clamp(10, 16).toDouble();

KoreaMapLabelDensity koreaMapLabelDensityForScale(double mapScale) {
  if (mapScale < 0.82) return KoreaMapLabelDensity.overview;
  if (mapScale < 2.15) return KoreaMapLabelDensity.regional;
  return KoreaMapLabelDensity.detailed;
}

double koreaMapCanvasFontSize({
  required double screenFontSize,
  required double mapScale,
}) {
  final safeMapScale = mapScale.clamp(0.34, 3.8).toDouble();
  return screenFontSize / safeMapScale;
}

class KoreaMapLabelPlacement {
  const KoreaMapLabelPlacement({
    required this.rect,
    required this.isCallout,
    required this.overlapsExisting,
  });

  final Rect rect;
  final bool isCallout;
  final bool overlapsExisting;

  Offset leaderEndFor(Offset anchor) => Offset(
        anchor.dx.clamp(rect.left, rect.right).toDouble(),
        anchor.dy.clamp(rect.top, rect.bottom).toDouble(),
      );
}

KoreaMapLabelPlacement placeKoreaMapLabel({
  required Rect mapRect,
  required Rect regionBounds,
  required Offset anchor,
  required Size inlineSize,
  required Size calloutSize,
  required double spacing,
  required Iterable<Rect> occupiedRects,
  bool forceCallout = false,
}) {
  final inlineRect = Rect.fromCenter(
      center: anchor, width: inlineSize.width, height: inlineSize.height);
  if (!forceCallout &&
      _containsRect(regionBounds, inlineRect) &&
      !_intersectsAny(inlineRect, occupiedRects)) {
    return KoreaMapLabelPlacement(
      rect: inlineRect,
      isCallout: false,
      overlapsExisting: false,
    );
  }

  final halfWidth = calloutSize.width / 2;
  final halfHeight = calloutSize.height / 2;
  final centers = <Offset>[
    Offset(anchor.dx, regionBounds.top - halfHeight - spacing),
    Offset(regionBounds.right + halfWidth + spacing, anchor.dy),
    Offset(regionBounds.left - halfWidth - spacing, anchor.dy),
    Offset(anchor.dx, regionBounds.bottom + halfHeight + spacing),
    Offset(
      regionBounds.right + halfWidth + spacing,
      regionBounds.top - halfHeight - spacing,
    ),
    Offset(
      regionBounds.left - halfWidth - spacing,
      regionBounds.top - halfHeight - spacing,
    ),
    Offset(
      regionBounds.right + halfWidth + spacing,
      regionBounds.bottom + halfHeight + spacing,
    ),
    Offset(
      regionBounds.left - halfWidth - spacing,
      regionBounds.bottom + halfHeight + spacing,
    ),
  ];

  KoreaMapLabelPlacement? leastOverlapping;
  var leastOverlapArea = double.infinity;
  for (final center in centers) {
    final rect = _clampRectToMap(
      Rect.fromCenter(
        center: center,
        width: calloutSize.width,
        height: calloutSize.height,
      ),
      mapRect,
    );
    final overlapArea = _overlapArea(rect, occupiedRects);
    if (overlapArea == 0) {
      return KoreaMapLabelPlacement(
        rect: rect,
        isCallout: true,
        overlapsExisting: false,
      );
    }
    if (overlapArea < leastOverlapArea) {
      leastOverlapArea = overlapArea;
      leastOverlapping = KoreaMapLabelPlacement(
        rect: rect,
        isCallout: true,
        overlapsExisting: true,
      );
    }
  }

  return leastOverlapping ??
      KoreaMapLabelPlacement(
        rect: _clampRectToMap(
          Rect.fromCenter(
            center: anchor,
            width: calloutSize.width,
            height: calloutSize.height,
          ),
          mapRect,
        ),
        isCallout: true,
        overlapsExisting: false,
      );
}

bool _containsRect(Rect outer, Rect inner) =>
    outer.contains(inner.topLeft) && outer.contains(inner.bottomRight);

bool _intersectsAny(Rect rect, Iterable<Rect> occupiedRects) =>
    occupiedRects.any(rect.overlaps);

double _overlapArea(Rect rect, Iterable<Rect> occupiedRects) {
  var area = 0.0;
  for (final occupied in occupiedRects) {
    final intersection = rect.intersect(occupied);
    if (!intersection.isEmpty) {
      area +=
          math.max(0, intersection.width) * math.max(0, intersection.height);
    }
  }
  return area;
}

Rect _clampRectToMap(Rect rect, Rect mapRect) {
  if (rect.width >= mapRect.width || rect.height >= mapRect.height) {
    return Rect.fromCenter(
      center: mapRect.center,
      width: math.min(rect.width, mapRect.width),
      height: math.min(rect.height, mapRect.height),
    );
  }
  final dx = rect.left < mapRect.left
      ? mapRect.left - rect.left
      : rect.right > mapRect.right
          ? mapRect.right - rect.right
          : 0.0;
  final dy = rect.top < mapRect.top
      ? mapRect.top - rect.top
      : rect.bottom > mapRect.bottom
          ? mapRect.bottom - rect.bottom
          : 0.0;
  return rect.shift(Offset(dx, dy));
}
