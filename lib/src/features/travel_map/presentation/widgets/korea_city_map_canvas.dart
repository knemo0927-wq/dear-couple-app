import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:couple_chat_app/src/features/travel_map/data/travel_map_repository.dart';
import 'package:couple_chat_app/src/features/travel_map/presentation/korea_map_label_layout.dart';
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
    required this.mapScale,
    this.currentLocationLngLat,
    super.key,
  });

  final List<TravelCity> cities;
  final Map<String, String> colorByCityId;
  final ValueChanged<TravelCity> onTapCity;
  final String? selectedCityId;
  final double mapScale;
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
          city.regionGroup,
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
    String? selectedCityName;
    for (final city in cities) {
      if (city.id == selectedCityId) {
        selectedCityName = city.name;
        break;
      }
    }

    return Semantics(
      key: const ValueKey('korea-map-canvas-semantics'),
      container: true,
      excludeSemantics: true,
      image: true,
      label:
          '대한민국 여행 지도 시각적 탐색용 캔버스. 전체 ${cities.length}개 지역 중 ${colorByCityId.length}개 지역 방문.${selectedCityName == null ? '' : ' 선택한 지역 $selectedCityName.'}${currentLocationLngLat == null ? '' : ' 현재 위치 표시 중.'}',
      hint: '지도는 확대하거나 이동해 탐색합니다. 화면 읽기 사용자는 장소 목록 열기 버튼으로 지역을 선택하세요.',
      child: FutureBuilder<_KoreaGeoMapData>(
        future: _geoCache,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('지도 데이터를 불러오지 못했어요.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final geo = snapshot.data!;
          final labelScreenFontSize =
              koreaMapScreenFontSize(MediaQuery.textScalerOf(context));
          final labelTextStyle = Theme.of(context).textTheme.labelMedium;
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

              return GestureDetector(
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
                    mapScale: mapScale,
                    labelScreenFontSize: labelScreenFontSize,
                    labelFontFamily: labelTextStyle?.fontFamily,
                    labelFontFamilyFallback: labelTextStyle?.fontFamilyFallback,
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
              );
            },
          );
        },
      ),
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
    required this.regionGroupLabelPoints,
    required this.cityBoundaryPaths,
    required this.mapRect,
  });

  final List<_PreparedRegion> regions;
  final Map<String, TravelCity> cityById;
  final Map<String, Offset> cityLabelPoints;
  final Map<String, Offset> regionGroupLabelPoints;
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
    final regionGroupBounds = <String, Rect>{};
    final cityIdsByRegionGroup = <String, List<String>>{};
    for (final entry in cityBoundaryPaths.entries) {
      final city = cityById[entry.key];
      final group = city?.regionGroup.trim() ?? '';
      final bounds = entry.value.getBounds();
      if (group.isEmpty || bounds.isEmpty) continue;
      regionGroupBounds.update(
        group,
        (current) => current.expandToInclude(bounds),
        ifAbsent: () => bounds,
      );
      cityIdsByRegionGroup.putIfAbsent(group, () => []).add(entry.key);
    }
    final regionGroupLabelPoints = <String, Offset>{};
    for (final entry in cityIdsByRegionGroup.entries) {
      final target = regionGroupBounds[entry.key]?.center;
      if (target == null) continue;
      Offset? nearest;
      var nearestDistance = double.infinity;
      for (final cityId in entry.value) {
        final point = cityLabelPoints[cityId];
        if (point == null) continue;
        final distance = (point - target).distanceSquared;
        if (distance < nearestDistance) {
          nearest = point;
          nearestDistance = distance;
        }
      }
      if (nearest != null) regionGroupLabelPoints[entry.key] = nearest;
    }

    return _PreparedKoreaMap(
      regions: preparedRegions,
      cityById: cityById,
      cityLabelPoints: cityLabelPoints,
      regionGroupLabelPoints: regionGroupLabelPoints,
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
    required this.mapScale,
    required this.labelScreenFontSize,
    required this.labelFontFamily,
    required this.labelFontFamilyFallback,
    required this.currentLocationPoint,
  });

  final _PreparedKoreaMap prepared;
  final Map<String, String> colorByCityId;
  final String? selectedCityId;
  final double mapScale;
  final double labelScreenFontSize;
  final String? labelFontFamily;
  final List<String>? labelFontFamilyFallback;
  final Offset? currentLocationPoint;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasUnitScale = 1 / mapScale.clamp(0.34, 3.8).toDouble();
    _drawSeaLabels(canvas, prepared.mapRect, canvasUnitScale);

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

    _drawAdaptiveRegionLabels(canvas, canvasUnitScale);

    final locationPoint = currentLocationPoint;
    if (locationPoint != null) {
      final markerScale = canvasUnitScale;
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

  void _drawAdaptiveRegionLabels(Canvas canvas, double canvasUnitScale) {
    final density = koreaMapLabelDensityForScale(mapScale);
    final occupiedRects = <Rect>[];
    final selectedCity =
        selectedCityId == null ? null : prepared.cityById[selectedCityId];
    final selectedPoint = selectedCityId == null
        ? null
        : prepared.cityLabelPoints[selectedCityId];
    if (selectedCity != null && selectedPoint != null) {
      occupiedRects.add(
        _selectedCityPillBounds(
          selectedPoint,
          _displayCityName(selectedCity.name),
          canvasUnitScale,
        ).inflate(3 * canvasUnitScale),
      );
    }
    final locationPoint = currentLocationPoint;
    if (locationPoint != null) {
      occupiedRects.add(
        Rect.fromCircle(
          center: locationPoint,
          radius: 15 * canvasUnitScale,
        ),
      );
    }

    final candidates = <_KoreaLabelCandidate>[];
    if (density == KoreaMapLabelDensity.overview) {
      for (final entry in prepared.regionGroupLabelPoints.entries) {
        if (selectedCity != null &&
            _displayCityName(selectedCity.name) == entry.key) {
          continue;
        }
        candidates.add(
          _KoreaLabelCandidate(
            id: 'group:${entry.key}',
            label: entry.key,
            anchor: entry.value,
            regionBounds: Rect.fromCircle(
              center: entry.value,
              radius: canvasUnitScale,
            ),
            cityPath: null,
            priority: 1,
            isGroup: true,
            allowOverlapFallback: true,
          ),
        );
      }
    }

    for (final entry in prepared.cityLabelPoints.entries) {
      final cityId = entry.key;
      if (cityId == selectedCityId) continue;
      final city = prepared.cityById[cityId];
      final cityPath = prepared.cityBoundaryPaths[cityId];
      if (city == null || cityPath == null) continue;
      final cityBounds = cityPath.getBounds();
      if (cityBounds.isEmpty) continue;
      final isVisited = colorByCityId.containsKey(cityId);
      if (density == KoreaMapLabelDensity.overview &&
          city.name.trim() == city.regionGroup.trim() &&
          prepared.regionGroupLabelPoints.containsKey(city.regionGroup)) {
        continue;
      }
      final shouldShow = switch (density) {
        KoreaMapLabelDensity.overview => isVisited,
        KoreaMapLabelDensity.regional =>
          isVisited || _isRegionalLabelCandidate(city, cityBounds),
        KoreaMapLabelDensity.detailed => true,
      };
      if (!shouldShow) continue;
      candidates.add(
        _KoreaLabelCandidate(
          id: cityId,
          label: _displayCityName(city.name),
          anchor: entry.value,
          regionBounds: cityBounds,
          cityPath: cityPath,
          priority: isVisited ? 2 : 3,
          isGroup: false,
          allowOverlapFallback:
              density == KoreaMapLabelDensity.detailed || isVisited,
        ),
      );
    }

    candidates.sort((left, right) {
      final priority = left.priority.compareTo(right.priority);
      if (priority != 0) return priority;
      final size = right.regionBounds.size.longestSide
          .compareTo(left.regionBounds.size.longestSide);
      if (size != 0) return size;
      return left.id.compareTo(right.id);
    });

    for (final candidate in candidates) {
      _drawLabelCandidate(
        canvas,
        candidate,
        canvasUnitScale,
        occupiedRects,
      );
    }

    if (selectedCity != null && selectedPoint != null) {
      _drawSelectedCityPill(
        canvas,
        selectedPoint,
        _displayCityName(selectedCity.name),
        canvasUnitScale,
      );
    }
  }

  bool _isRegionalLabelCandidate(TravelCity city, Rect bounds) {
    if (city.code.startsWith('METRO_')) return true;
    final screenWidth = bounds.width * mapScale;
    final screenHeight = bounds.height * mapScale;
    return screenWidth >= 46 && screenHeight >= 26;
  }

  void _drawLabelCandidate(
    Canvas canvas,
    _KoreaLabelCandidate candidate,
    double canvasUnitScale,
    List<Rect> occupiedRects,
  ) {
    final screenFontSize = candidate.isGroup
        ? (labelScreenFontSize + 1).clamp(11, 17).toDouble()
        : labelScreenFontSize;
    final fontSize = koreaMapCanvasFontSize(
      screenFontSize: screenFontSize,
      mapScale: mapScale,
    );
    final textPainter = _buildLabelPainter(
      candidate.label,
      fontSize: fontSize,
      color:
          candidate.isGroup ? const Color(0xFF9D3A61) : const Color(0xFF6D4F59),
      fontWeight: candidate.isGroup ? FontWeight.w900 : FontWeight.w800,
    );
    final inlineRect = Rect.fromCenter(
      center: candidate.anchor,
      width: textPainter.width,
      height: textPainter.height,
    );
    final forceCallout = candidate.isGroup ||
        candidate.cityPath == null ||
        !_pathContainsRect(candidate.cityPath!, inlineRect);
    final placement = placeKoreaMapLabel(
      mapRect: prepared.mapRect,
      regionBounds: forceCallout
          ? _calloutOriginBounds(
              candidate.regionBounds,
              candidate.anchor,
              canvasUnitScale,
            )
          : candidate.regionBounds,
      anchor: candidate.anchor,
      inlineSize: textPainter.size,
      calloutSize: Size(
        textPainter.width + 12 * canvasUnitScale,
        textPainter.height + 8 * canvasUnitScale,
      ),
      spacing: 5 * canvasUnitScale,
      occupiedRects: occupiedRects,
      forceCallout: forceCallout,
    );
    if (placement.overlapsExisting && !candidate.allowOverlapFallback) return;

    if (placement.isCallout) {
      _drawCalloutLabel(
        canvas,
        candidate: candidate,
        placement: placement,
        textPainter: textPainter,
        canvasUnitScale: canvasUnitScale,
      );
    } else {
      _drawInlineLabel(
        canvas,
        candidate.label,
        placement.rect.topLeft,
        textPainter,
        canvasUnitScale,
      );
    }
    occupiedRects.add(placement.rect.inflate(3 * canvasUnitScale));
  }

  Rect _calloutOriginBounds(
    Rect regionBounds,
    Offset anchor,
    double canvasUnitScale,
  ) {
    final localBounds = Rect.fromCenter(
      center: anchor,
      width: 40 * canvasUnitScale,
      height: 40 * canvasUnitScale,
    );
    final bounded = regionBounds.intersect(localBounds);
    return bounded.isEmpty
        ? Rect.fromCircle(center: anchor, radius: canvasUnitScale)
        : bounded;
  }

  TextPainter _buildLabelPainter(
    String label, {
    required double fontSize,
    required Color color,
    required FontWeight fontWeight,
    Paint? foreground,
  }) {
    return TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: foreground == null ? color : null,
          foreground: foreground,
          fontFamily: labelFontFamily,
          fontFamilyFallback: labelFontFamilyFallback,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1,
        ),
      ),
    )..layout();
  }

  void _drawInlineLabel(
    Canvas canvas,
    String label,
    Offset offset,
    TextPainter textPainter,
    double canvasUnitScale,
  ) {
    final outline = _buildLabelPainter(
      label,
      fontSize: textPainter.text?.style?.fontSize ?? 11 * canvasUnitScale,
      color: Colors.white,
      fontWeight: FontWeight.w800,
      foreground: Paint()
        ..color = Colors.white.withValues(alpha: 0.96)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * canvasUnitScale,
    );
    outline.paint(canvas, offset);
    textPainter.paint(canvas, offset);
  }

  void _drawCalloutLabel(
    Canvas canvas, {
    required _KoreaLabelCandidate candidate,
    required KoreaMapLabelPlacement placement,
    required TextPainter textPainter,
    required double canvasUnitScale,
  }) {
    final leaderEnd = placement.leaderEndFor(candidate.anchor);
    canvas.drawLine(
      candidate.anchor,
      leaderEnd,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.96)
        ..strokeWidth = 3.6 * canvasUnitScale
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      candidate.anchor,
      leaderEnd,
      Paint()
        ..color = candidate.isGroup
            ? const Color(0xFFD05C86)
            : const Color(0xFFB76983)
        ..strokeWidth = 1.35 * canvasUnitScale
        ..strokeCap = StrokeCap.round,
    );

    final rrect = RRect.fromRectAndRadius(
      placement.rect,
      Radius.circular(6 * canvasUnitScale),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = candidate.isGroup
            ? const Color(0xFFFFF7FA).withValues(alpha: 0.97)
            : Colors.white.withValues(alpha: 0.94),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = candidate.isGroup
            ? const Color(0xFFE58EAC)
            : const Color(0xFFE6BBC8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = canvasUnitScale,
    );
    textPainter.paint(
      canvas,
      placement.rect.center -
          Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  bool _pathContainsRect(Path path, Rect rect) =>
      path.contains(rect.topLeft) &&
      path.contains(rect.topRight) &&
      path.contains(rect.bottomLeft) &&
      path.contains(rect.bottomRight) &&
      path.contains(rect.center);

  void _drawSeaLabels(
    Canvas canvas,
    Rect mapRect,
    double canvasUnitScale,
  ) {
    _drawMapLabel(
      canvas,
      '서해',
      Offset(
        mapRect.left + mapRect.width * 0.13,
        mapRect.top + mapRect.height * 0.48,
      ),
      canvasUnitScale,
    );
    _drawMapLabel(
      canvas,
      '동해',
      Offset(
        mapRect.left + mapRect.width * 0.77,
        mapRect.top + mapRect.height * 0.34,
      ),
      canvasUnitScale,
    );
    _drawMapLabel(
      canvas,
      '대한해협',
      Offset(
        mapRect.left + mapRect.width * 0.52,
        mapRect.top + mapRect.height * 0.79,
      ),
      canvasUnitScale,
    );
  }

  void _drawMapLabel(
    Canvas canvas,
    String label,
    Offset center,
    double canvasUnitScale,
  ) {
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: const Color(0xFF96B7C7),
          fontSize: 14 * canvasUnitScale,
          fontFamily: labelFontFamily,
          fontFamilyFallback: labelFontFamilyFallback,
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

  Rect _selectedCityPillBounds(
    Offset center,
    String label,
    double canvasUnitScale,
  ) {
    final fontSize =
        (labelScreenFontSize + 3).clamp(14, 19).toDouble() * canvasUnitScale;
    final textPainter = _buildLabelPainter(
      label,
      fontSize: fontSize,
      color: Colors.white,
      fontWeight: FontWeight.w900,
    );
    final pillRect = Rect.fromCenter(
      center: center.translate(0, -20 * canvasUnitScale),
      width: textPainter.width + 26 * canvasUnitScale,
      height: textPainter.height + 16 * canvasUnitScale,
    );
    return pillRect.expandToInclude(
      Rect.fromCircle(
        center: center.translate(0, 7 * canvasUnitScale),
        radius: 7 * canvasUnitScale,
      ),
    );
  }

  void _drawSelectedCityPill(
    Canvas canvas,
    Offset center,
    String label,
    double canvasUnitScale,
  ) {
    final fontSize =
        (labelScreenFontSize + 3).clamp(14, 19).toDouble() * canvasUnitScale;
    final textPainter = _buildLabelPainter(
      label,
      fontSize: fontSize,
      color: Colors.white,
      fontWeight: FontWeight.w900,
    );

    final pillRect = Rect.fromCenter(
      center: center.translate(0, -20 * canvasUnitScale),
      width: textPainter.width + 26 * canvasUnitScale,
      height: textPainter.height + 16 * canvasUnitScale,
    );
    final rrect = RRect.fromRectAndRadius(
      pillRect,
      Radius.circular(12 * canvasUnitScale),
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
      center.translate(0, 7 * canvasUnitScale),
      4.2 * canvasUnitScale,
      Paint()..color = const Color(0xFFEF6F89),
    );
    canvas.drawCircle(
      center.translate(0, 7 * canvasUnitScale),
      6.8 * canvasUnitScale,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * canvasUnitScale,
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
        oldDelegate.mapScale != mapScale ||
        oldDelegate.labelScreenFontSize != labelScreenFontSize ||
        oldDelegate.labelFontFamily != labelFontFamily ||
        oldDelegate.labelFontFamilyFallback != labelFontFamilyFallback ||
        oldDelegate.currentLocationPoint != currentLocationPoint;
  }
}

class _KoreaLabelCandidate {
  const _KoreaLabelCandidate({
    required this.id,
    required this.label,
    required this.anchor,
    required this.regionBounds,
    required this.cityPath,
    required this.priority,
    required this.isGroup,
    required this.allowOverlapFallback,
  });

  final String id;
  final String label;
  final Offset anchor;
  final Rect regionBounds;
  final Path? cityPath;
  final int priority;
  final bool isGroup;
  final bool allowOverlapFallback;
}
