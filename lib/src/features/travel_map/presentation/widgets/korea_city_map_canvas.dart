import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 2025 SGIS 시군구 경계의 실제 최외곽 좌표에 약 0.08도 여백을 둔 범위다.
// 도시 중심점으로 범위를 추정하면 옹진군·울릉군과 남해의 섬이 잘리므로 지도와
// 현재 위치 마커가 모두 이 고정 범위를 공유한다.
const double _koreaViewMinLng = 124.53;
const double _koreaViewMaxLng = 131.96;
const double _koreaViewMinLat = 33.03;
const double _koreaViewMaxLat = 38.70;

bool isWithinKoreaMapBounds({
  required double latitude,
  required double longitude,
}) {
  return latitude >= _koreaViewMinLat &&
      latitude <= _koreaViewMaxLat &&
      longitude >= _koreaViewMinLng &&
      longitude <= _koreaViewMaxLng;
}

Offset projectKoreaLocationToCanvas({
  required Size size,
  required List<TravelCity> cities,
  required double latitude,
  required double longitude,
}) {
  if (size.isEmpty) return size.center(Offset.zero);
  return _KoreaMapProjection.forSize(size).project(
    Offset(longitude, latitude),
  );
}

/// 공식 시군구 경계를 앱의 여행 지역 단위에 정확히 연결한다.
///
/// 광역시는 하나의 여행 지역으로, 일반시의 비자치구는 부모 시로 합친다. 그 외
/// 시·군은 공식 SIG 코드를 직접 사용한다. 이름이나 거리로 추측하지 않으므로
/// 경기 광주와 광주광역시, 강원 고성과 경남 고성도 서로 섞이지 않는다.
TravelCity? matchTravelCityForKoreaAdministrativeRegion({
  required String code,
  required String name,
  required List<TravelCity> cities,
}) {
  final normalizedCode = code.trim();

  // 광역 단위가 해당 자치구·군 전체를 소유한다.
  for (final city in cities) {
    final metroPrefix = _metroPrefixForCity(city);
    if (metroPrefix != null && normalizedCode.startsWith(metroPrefix)) {
      return city;
    }
  }

  // 동명 지역보다 공식 코드를 항상 우선한다.
  for (final city in cities) {
    final cityCode = city.code.trim();
    if (cityCode.startsWith('SIG_') &&
        cityCode.substring(4) == normalizedCode) {
      return city;
    }
  }

  // 기존 앱에서 이미 하나의 방문 기록 단위였던 복합시와 코드가 변경된 군은
  // 명시적인 공식 코드 목록으로만 연결한다. 신규 안양·부천·안산도 같은 원칙을
  // 적용해 각 행정구가 하나의 부모 도시 기록을 공유한다.
  for (final city in cities) {
    final administrativeCodes = _administrativeCodesByTravelCityCode[city.code];
    if (administrativeCodes?.contains(normalizedCode) ?? false) {
      return city;
    }
  }
  return null;
}

const Map<String, Set<String>> _administrativeCodesByTravelCityCode = {
  'SIG_31014': {'31011', '31012', '31013', '31014'}, // 수원
  'SIG_31023': {'31021', '31022', '31023'}, // 성남
  'SIG_31041': {'31041', '31042'}, // 안양
  'SIG_31051': {'31051', '31052', '31053'}, // 부천
  'SIG_31091': {'31091', '31092'}, // 안산
  'SIG_31104': {'31101', '31103', '31104'}, // 고양
  'SIG_31193': {'31191', '31192', '31193'}, // 용인
  'SIG_31370': {'31570'}, // 가평: 2013 코드 -> 2025 코드
  'SIG_32340': {'32540'}, // 평창: 2013 코드 -> 2025 코드
  'SIG_32410': {'32610'}, // 양양: 2013 코드 -> 2025 코드
  'SIG_33011': {'33041', '33042', '33043', '33044'}, // 청주
  'SIG_34011': {'34011', '34012'}, // 천안
  'SIG_35011': {'35011', '35012'}, // 전주
  'SIG_37011': {'37011', '37012'}, // 포항
  'SIG_38111': {'38111', '38112', '38113', '38114', '38115'}, // 창원
};

String? _metroPrefixForCity(TravelCity city) {
  final code = city.code.trim();
  if (!code.startsWith('METRO_')) return null;
  final prefix = code.substring('METRO_'.length);
  return RegExp(r'^\d{2}$').hasMatch(prefix) ? prefix : null;
}

class _KoreaMapProjection {
  const _KoreaMapProjection({
    required this.mapRect,
    required this.minMercatorY,
    required this.maxMercatorY,
  });

  final Rect mapRect;
  final double minMercatorY;
  final double maxMercatorY;

  factory _KoreaMapProjection.forSize(Size size) {
    final minY = _mercatorY(_koreaViewMinLat);
    final maxY = _mercatorY(_koreaViewMaxLat);
    final geoAspect = (_koreaViewMaxLng - _koreaViewMinLng) / (maxY - minY);
    final availableAspect = size.width / size.height;
    final Rect rect;
    if (availableAspect > geoAspect) {
      final width = size.height * geoAspect;
      rect = Rect.fromLTWH((size.width - width) / 2, 0, width, size.height);
    } else {
      final height = size.width / geoAspect;
      rect = Rect.fromLTWH(0, (size.height - height) / 2, size.width, height);
    }
    return _KoreaMapProjection(
      mapRect: rect,
      minMercatorY: minY,
      maxMercatorY: maxY,
    );
  }

  Offset project(Offset lngLat) {
    final xFraction =
        (lngLat.dx - _koreaViewMinLng) / (_koreaViewMaxLng - _koreaViewMinLng);
    final yFraction =
        (maxMercatorY - _mercatorY(lngLat.dy)) / (maxMercatorY - minMercatorY);
    return Offset(
      mapRect.left + xFraction * mapRect.width,
      mapRect.top + yFraction * mapRect.height,
    );
  }

  static double _mercatorY(double latitude) {
    final radians = latitude * math.pi / 180;
    return math.log(math.tan(math.pi / 4 + radians / 2)) * 180 / math.pi;
  }
}

class KoreaCityMapCanvas extends StatelessWidget {
  const KoreaCityMapCanvas({
    required this.cities,
    required this.colorByCityId,
    required this.onTapCity,
    required this.selectedCityId,
    required this.labelScaleFactor,
    this.currentLocationLngLat,
    super.key,
  });

  final List<TravelCity> cities;
  final Map<String, String> colorByCityId;
  final ValueChanged<TravelCity> onTapCity;
  final String? selectedCityId;
  final double labelScaleFactor;
  final Offset? currentLocationLngLat;

  static Future<_KoreaGeoMapData>? _geoCache;
  static _PreparedKoreaMapCacheEntry? _preparedCache;

  static _PreparedKoreaMap _preparedMap({
    required Size size,
    required _KoreaGeoMapData geo,
    required List<TravelCity> cities,
  }) {
    final citySignature = Object.hashAll(
      cities.map(
        (city) => Object.hash(
          city.id,
          city.code,
          city.name,
          city.centerLat,
          city.centerLng,
        ),
      ),
    );
    final cached = _preparedCache;
    if (cached != null &&
        identical(cached.geo, geo) &&
        cached.size == size &&
        cached.citySignature == citySignature &&
        cached.cityCount == cities.length) {
      return cached.prepared;
    }

    final prepared = _PreparedKoreaMap.build(
      size: size,
      geo: geo,
      cities: cities,
    );
    _preparedCache = _PreparedKoreaMapCacheEntry(
      geo: geo,
      size: size,
      citySignature: citySignature,
      cityCount: cities.length,
      prepared: prepared,
    );
    return prepared;
  }

  @override
  Widget build(BuildContext context) {
    if (cities.isEmpty) {
      return const Center(child: Text('지역 데이터를 불러오는 중...'));
    }

    _geoCache ??= _KoreaGeoMapData.load();

    return FutureBuilder<_KoreaGeoMapData>(
      future: _geoCache,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('지도 데이터를 불러오지 못했어요.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final geo = snapshot.data!;
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(
              constraints.maxWidth.isFinite ? constraints.maxWidth : 360,
              constraints.maxHeight.isFinite ? constraints.maxHeight : 520,
            );
            final prepared = _preparedMap(
              size: size,
              geo: geo,
              cities: cities,
            );

            return Semantics(
              container: true,
              label:
                  '대한민국 여행 지도. 전체 ${cities.length}개 지역 중 ${colorByCityId.length}개 지역 방문.${currentLocationLngLat == null ? '' : ' 현재 위치 표시 중.'}',
              hint: '지도를 확대하거나 이동한 뒤 지역을 선택할 수 있어요.',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final local = details.localPosition;
                  for (final region in prepared.regions) {
                    final cityId = region.assignedCityId;
                    if (cityId == null) continue;
                    for (final path in region.paths) {
                      if (!path.contains(local)) continue;
                      final city = prepared.cityById[cityId];
                      if (city != null) onTapCity(city);
                      return;
                    }
                  }
                },
                child: CustomPaint(
                  size: size,
                  painter: _KoreaAdministrativeMapPainter(
                    prepared: prepared,
                    colorByCityId: colorByCityId,
                    selectedCityId: selectedCityId,
                    labelScaleFactor: labelScaleFactor,
                    currentLocationPoint: currentLocationLngLat == null
                        ? null
                        : projectKoreaLocationToCanvas(
                            size: size,
                            cities: cities,
                            latitude: currentLocationLngLat!.dy,
                            longitude: currentLocationLngLat!.dx,
                          ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Color parseHexColor(String? value) {
    if (value == null) return const Color(0xFFFBF7EF);
    final hex = value.replaceAll('#', '');
    if (hex.length != 6) return const Color(0xFFFBF7EF);
    return Color(int.parse('FF$hex', radix: 16));
  }
}

class _PreparedKoreaMapCacheEntry {
  const _PreparedKoreaMapCacheEntry({
    required this.geo,
    required this.size,
    required this.citySignature,
    required this.cityCount,
    required this.prepared,
  });

  final _KoreaGeoMapData geo;
  final Size size;
  final int citySignature;
  final int cityCount;
  final _PreparedKoreaMap prepared;
}

class _KoreaGeoMapData {
  const _KoreaGeoMapData({required this.regions});

  final List<_GeoRegion> regions;

  static Future<_KoreaGeoMapData> load() async {
    final raw = await rootBundle
        .loadString('assets/maps/skorea_municipalities_geo_simple.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final features = decoded['features'] as List<dynamic>;

    final regions = <_GeoRegion>[];

    for (final feature in features) {
      final map = feature as Map<String, dynamic>;
      final props = map['properties'] as Map<String, dynamic>;
      final geometry = map['geometry'] as Map<String, dynamic>;
      final type = geometry['type'] as String;
      final coordinates = geometry['coordinates'];

      final polygons = <List<List<Offset>>>[];
      if (type == 'Polygon') {
        polygons.add(_parsePolygon(coordinates));
      } else if (type == 'MultiPolygon') {
        for (final polygon in coordinates as List<dynamic>) {
          polygons.add(_parsePolygon(polygon));
        }
      }

      regions.add(_GeoRegion(
        code: (props['code'] as String?) ?? '',
        name: (props['name'] as String?) ?? '',
        polygons: polygons,
      ));
    }

    return _KoreaGeoMapData(regions: regions);
  }

  static List<List<Offset>> _parsePolygon(dynamic polygon) {
    final rings = <List<Offset>>[];
    for (final ringRaw in polygon as List<dynamic>) {
      final ring = <Offset>[];
      for (final pointRaw in ringRaw as List<dynamic>) {
        final point = pointRaw as List<dynamic>;
        final lng = (point[0] as num).toDouble();
        final lat = (point[1] as num).toDouble();
        ring.add(Offset(lng, lat));
      }
      if (ring.length >= 3) rings.add(ring);
    }
    return rings;
  }
}

class _GeoRegion {
  const _GeoRegion(
      {required this.code, required this.name, required this.polygons});

  final String code;
  final String name;
  final List<List<List<Offset>>> polygons;
}

class _PreparedKoreaMap {
  const _PreparedKoreaMap({
    required this.regions,
    required this.cityById,
    required this.cityLabelPoints,
    required this.cityBoundaryPaths,
    required this.mapRect,
  });

  final List<_PreparedRegion> regions;
  final Map<String, TravelCity> cityById;
  final Map<String, Offset> cityLabelPoints;
  final Map<String, Path> cityBoundaryPaths;
  final Rect mapRect;

  static _PreparedKoreaMap build({
    required Size size,
    required _KoreaGeoMapData geo,
    required List<TravelCity> cities,
  }) {
    final projection = _KoreaMapProjection.forSize(size);

    final preparedRegions = <_PreparedRegion>[];
    for (final region in geo.regions) {
      final paths = <Path>[];
      for (final polygon in region.polygons) {
        if (polygon.isEmpty) continue;
        final path = Path()..fillType = PathFillType.evenOdd;
        for (var ringIndex = 0; ringIndex < polygon.length; ringIndex++) {
          final ring = polygon[ringIndex];
          if (ring.isEmpty) continue;
          final first = projection.project(ring.first);
          path.moveTo(first.dx, first.dy);
          for (final p in ring.skip(1)) {
            final projected = projection.project(p);
            path.lineTo(projected.dx, projected.dy);
          }
          path.close();
        }
        paths.add(path);
      }

      final assignedCity = matchTravelCityForKoreaAdministrativeRegion(
        code: region.code,
        name: region.name,
        cities: cities,
      );
      preparedRegions.add(_PreparedRegion(
        name: region.name,
        assignedCityId: assignedCity?.id,
        paths: paths,
      ));
    }

    final cityById = {for (final city in cities) city.id: city};
    final cityBoundaryPaths = <String, Path>{};
    for (final region in preparedRegions) {
      final cityId = region.assignedCityId;
      if (cityId == null) continue;
      for (final path in region.paths) {
        final current = cityBoundaryPaths[cityId];
        if (current == null) {
          cityBoundaryPaths[cityId] = Path()
            ..fillType = PathFillType.evenOdd
            ..addPath(path, Offset.zero);
        } else {
          // 공식 경계는 이미 서로 맞닿는 topology를 공유한다. 고해상도 도서
          // polygon을 매 프레임 boolean-union하면 초기 렌더가 수십 초 걸릴 수
          // 있으므로 하나의 compound path에 추가해 동일한 채움/탭 영역을 만든다.
          current.addPath(path, Offset.zero);
        }
      }
    }

    // 공식 도시 중심점이 실제 경계 안에 있으면 그 위치를 우선한다. 인천·목포처럼
    // 섬이 많은 지역도 가장 큰 섬의 bounding box에 라벨이 끌려가지 않는다.
    final labelCandidates = <String, _LabelCandidate>{};
    for (final region in preparedRegions) {
      final cityId = region.assignedCityId;
      if (cityId == null) continue;
      for (final path in region.paths) {
        final bounds = path.getBounds();
        if (bounds.isEmpty) continue;
        final area = bounds.width * bounds.height;
        final current = labelCandidates[cityId];
        if (current == null || area > current.area) {
          labelCandidates[cityId] = _LabelCandidate(
            point: _labelPointForPath(path),
            area: area,
          );
        }
      }
    }
    final cityLabelPoints = {
      for (final entry in cityBoundaryPaths.entries)
        entry.key: _preferredCityLabelPoint(
          city: cityById[entry.key],
          cityPath: entry.value,
          projection: projection,
          fallback: labelCandidates[entry.key]?.point ??
              entry.value.getBounds().center,
        ),
    };

    return _PreparedKoreaMap(
      regions: preparedRegions,
      cityById: cityById,
      cityLabelPoints: cityLabelPoints,
      cityBoundaryPaths: cityBoundaryPaths,
      mapRect: projection.mapRect,
    );
  }

  static Offset _preferredCityLabelPoint({
    required TravelCity? city,
    required Path cityPath,
    required _KoreaMapProjection projection,
    required Offset fallback,
  }) {
    if (city == null) return fallback;
    final projectedCenter = projection.project(
      Offset(city.centerLng, city.centerLat),
    );
    return cityPath.contains(projectedCenter) ? projectedCenter : fallback;
  }

  static Offset _labelPointForPath(Path path) {
    final bounds = path.getBounds();
    final center = bounds.center;
    if (path.contains(center)) return center;

    Offset? best;
    var bestDistance = double.infinity;
    for (var row = 1; row <= 5; row++) {
      for (var col = 1; col <= 5; col++) {
        final point = Offset(
          bounds.left + bounds.width * col / 6,
          bounds.top + bounds.height * row / 6,
        );
        if (!path.contains(point)) continue;
        final distance = (point - center).distanceSquared;
        if (distance < bestDistance) {
          best = point;
          bestDistance = distance;
        }
      }
    }

    return best ?? center;
  }
}

class _LabelCandidate {
  const _LabelCandidate({required this.point, required this.area});

  final Offset point;
  final double area;
}

class _PreparedRegion {
  const _PreparedRegion({
    required this.name,
    required this.assignedCityId,
    required this.paths,
  });

  final String name;
  final String? assignedCityId;
  final List<Path> paths;
}

class _KoreaAdministrativeMapPainter extends CustomPainter {
  _KoreaAdministrativeMapPainter({
    required this.prepared,
    required this.colorByCityId,
    required this.selectedCityId,
    required this.labelScaleFactor,
    required this.currentLocationPoint,
  });

  final _PreparedKoreaMap prepared;
  final Map<String, String> colorByCityId;
  final String? selectedCityId;
  final double labelScaleFactor;
  final Offset? currentLocationPoint;

  @override
  void paint(Canvas canvas, Size size) {
    _drawSeaLabels(canvas, prepared.mapRect);

    final landFillPaint = Paint()
      ..color = const Color(0xFFFBF7EF)
      ..style = PaintingStyle.fill;
    final administrativeBoundaryPaint = Paint()
      ..color = const Color(0xFFF0DDE1)
      ..strokeWidth = 0.65
      ..style = PaintingStyle.stroke;

    // 전국 시군구를 먼저 기본색으로 그리고, 서버에서 받은 여행 지역을 정확한
    // 행정경계로 덮어쓴다. 전체 카탈로그 마이그레이션 적용 후 252개 경계가 모두
    // 161개 여행 지역 중 하나에 연결된다.
    for (final region in prepared.regions) {
      for (final path in region.paths) {
        canvas.drawPath(path, landFillPaint);
        canvas.drawPath(path, administrativeBoundaryPaint);
      }
    }

    final boundaryPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    final selectedPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.4
      ..style = PaintingStyle.stroke;

    for (final entry in prepared.cityBoundaryPaths.entries) {
      final rawFill =
          KoreaCityMapCanvas.parseHexColor(colorByCityId[entry.key]);
      final fill = colorByCityId.containsKey(entry.key)
          ? _softVisitedColor(rawFill)
          : rawFill;
      canvas.drawPath(
        entry.value,
        Paint()
          ..color = fill
          ..style = PaintingStyle.fill,
      );
    }

    for (final entry in prepared.cityBoundaryPaths.entries) {
      final isSelected = selectedCityId == entry.key;
      canvas.drawPath(entry.value, isSelected ? selectedPaint : boundaryPaint);
    }

    final outerPaint = Paint()
      ..color = const Color(0xFFF2D3D8)
      ..strokeWidth = 0.95
      ..style = PaintingStyle.stroke;
    for (final entry in prepared.cityBoundaryPaths.entries) {
      canvas.drawPath(entry.value, outerPaint);
    }

    final safeLabelScale = labelScaleFactor.clamp(0.28, 1.0).toDouble();
    prepared.cityLabelPoints.forEach((cityId, point) {
      final city = prepared.cityById[cityId];
      if (city == null) return;
      final label = _displayCityName(city.name);
      final selected = selectedCityId == cityId;
      final shouldShowRegionLabel = labelScaleFactor <= 0.98;
      if (!selected && !shouldShowRegionLabel) return;
      final fontSize = (selected ? 15.0 : 12.4) * safeLabelScale;
      final cityPath = prepared.cityBoundaryPaths[cityId];
      final cityBounds = cityPath?.getBounds();
      if (cityPath == null || cityBounds == null || cityBounds.isEmpty) return;

      if (selected) {
        _drawSelectedCityPill(canvas, point, label, safeLabelScale);
        return;
      }

      final fittedLabel = _fitRegionLabel(
        label: label,
        cityBounds: cityBounds,
        preferredCenter: point,
        maxFontSize: fontSize,
      );
      if (fittedLabel == null) return;
      fittedLabel.painter.paint(canvas, fittedLabel.offset);
    });

    final locationPoint = currentLocationPoint;
    if (locationPoint != null) {
      final markerScale = labelScaleFactor.clamp(0.28, 1.0).toDouble();
      canvas.drawCircle(
        locationPoint,
        12 * markerScale,
        Paint()..color = const Color(0xFF3478F6).withValues(alpha: 0.2),
      );
      canvas.drawCircle(
        locationPoint,
        7 * markerScale,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        locationPoint,
        4.5 * markerScale,
        Paint()..color = const Color(0xFF3478F6),
      );
    }
  }

  Color _softVisitedColor(Color color) {
    return Color.lerp(color, Colors.white, 0.28)!.withValues(alpha: 0.92);
  }

  void _drawSeaLabels(Canvas canvas, Rect mapRect) {
    _drawMapLabel(
      canvas,
      '서해',
      Offset(
        mapRect.left + mapRect.width * 0.13,
        mapRect.top + mapRect.height * 0.48,
      ),
    );
    _drawMapLabel(
      canvas,
      '동해',
      Offset(
        mapRect.left + mapRect.width * 0.77,
        mapRect.top + mapRect.height * 0.34,
      ),
    );
    _drawMapLabel(
      canvas,
      '대한해협',
      Offset(
        mapRect.left + mapRect.width * 0.52,
        mapRect.top + mapRect.height * 0.79,
      ),
    );
  }

  void _drawMapLabel(Canvas canvas, String label, Offset center) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Color(0xFF96B7C7),
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawSelectedCityPill(
    Canvas canvas,
    Offset center,
    String label,
    double scale,
  ) {
    final fontSize = 15.0 * scale;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    )..layout();

    final pillRect = Rect.fromCenter(
      center: center.translate(0, -18 * scale),
      width: textPainter.width + 26 * scale,
      height: textPainter.height + 16 * scale,
    );
    final rrect = RRect.fromRectAndRadius(
      pillRect,
      Radius.circular(12 * scale),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFFEF6F89)
        ..style = PaintingStyle.fill,
    );
    textPainter.paint(
      canvas,
      pillRect.center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
    canvas.drawCircle(
      center.translate(0, 7 * scale),
      4.2 * scale,
      Paint()..color = const Color(0xFFEF6F89),
    );
    canvas.drawCircle(
      center.translate(0, 7 * scale),
      6.8 * scale,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale,
    );
  }

  _FittedRegionLabel? _fitRegionLabel({
    required String label,
    required Rect cityBounds,
    required Offset preferredCenter,
    required double maxFontSize,
  }) {
    const minFontSize = 1.8;
    final largestFontSize = math.max(minFontSize, maxFontSize);

    TextPainter buildPainter(double fontSize) => TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: fontSize,
              color: const Color(0xFF6D4F59),
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        )..layout();

    var textPainter = buildPainter(largestFontSize);
    final widthScale = cityBounds.width <= 0
        ? 0.0
        : cityBounds.width * 0.82 / textPainter.width;
    final heightScale = cityBounds.height <= 0
        ? 0.0
        : cityBounds.height * 0.70 / textPainter.height;
    final fitScale = math.min(1.0, math.min(widthScale, heightScale));
    if (fitScale <= 0) return null;
    final fittedFontSize =
        (largestFontSize * fitScale).clamp(minFontSize, largestFontSize);
    if ((fittedFontSize - largestFontSize).abs() > 0.01) {
      textPainter = buildPainter(fittedFontSize.toDouble());
    }

    final halfWidth = textPainter.width / 2;
    final halfHeight = textPainter.height / 2;
    if (cityBounds.width < textPainter.width ||
        cityBounds.height < textPainter.height) {
      return null;
    }
    final center = Offset(
      preferredCenter.dx
          .clamp(cityBounds.left + halfWidth, cityBounds.right - halfWidth)
          .toDouble(),
      preferredCenter.dy
          .clamp(cityBounds.top + halfHeight, cityBounds.bottom - halfHeight)
          .toDouble(),
    );
    return _FittedRegionLabel(
      painter: textPainter,
      offset: center - Offset(halfWidth, halfHeight),
    );
  }

  String _displayCityName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;

    // '대구', '영구'처럼 실제 지명 마지막 글자가 '구'인 2글자 도시는 줄이면 안 된다.
    // 3글자 이상에서만 행정구역 접미사(시/군/구)를 제거한다.
    final withoutSuffix = trimmed.length >= 3
        ? trimmed.replaceFirst(RegExp(r'(시|군|구)$'), '')
        : trimmed;
    return withoutSuffix.length <= 4
        ? withoutSuffix
        : withoutSuffix.substring(0, 4);
  }

  @override
  bool shouldRepaint(covariant _KoreaAdministrativeMapPainter oldDelegate) {
    return oldDelegate.prepared != prepared ||
        oldDelegate.colorByCityId != colorByCityId ||
        oldDelegate.selectedCityId != selectedCityId ||
        oldDelegate.labelScaleFactor != labelScaleFactor ||
        oldDelegate.currentLocationPoint != currentLocationPoint;
  }
}

class _FittedRegionLabel {
  const _FittedRegionLabel({
    required this.painter,
    required this.offset,
  });

  final TextPainter painter;
  final Offset offset;
}
