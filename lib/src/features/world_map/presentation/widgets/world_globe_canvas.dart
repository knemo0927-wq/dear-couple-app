import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GlobeCountryShape {
  const GlobeCountryShape({
    required this.code,
    required this.name,
    required this.labelLngLat,
    required this.polygons,
  });

  final String code;
  final String name;
  final Offset labelLngLat;
  final List<List<List<Offset>>> polygons; // polygon -> rings -> lng/lat points
}

Future<List<GlobeCountryShape>> loadWorldCountryShapes() async {
  final raw = await rootBundle
      .loadString('assets/maps/world_countries_globe_simple.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final features = json['features'] as List;
  return features.map((feature) {
    final map = Map<String, dynamic>.from(feature as Map);
    final properties = Map<String, dynamic>.from(map['properties'] as Map);
    final geometry = Map<String, dynamic>.from(map['geometry'] as Map);
    final polygons = <List<List<Offset>>>[];
    for (final poly in geometry['coordinates'] as List) {
      final rings = <List<Offset>>[];
      for (final ring in poly as List) {
        rings.add((ring as List).map((point) {
          final p = point as List;
          return Offset((p[0] as num).toDouble(), (p[1] as num).toDouble());
        }).toList(growable: false));
      }
      if (rings.isNotEmpty) polygons.add(rings);
    }
    return GlobeCountryShape(
      code: properties['code'] as String,
      name: (properties['name_ko'] as String?) ??
          (properties['name_en'] as String? ?? ''),
      labelLngLat: _computeLabelLngLat(polygons),
      polygons: polygons,
    );
  }).toList(growable: false);
}

Offset _computeLabelLngLat(List<List<List<Offset>>> polygons) {
  Rect? bestBounds;
  var bestArea = -1.0;

  for (final polygon in polygons) {
    for (final ring in polygon) {
      if (ring.length < 3) continue;
      var minLng = double.infinity;
      var maxLng = -double.infinity;
      var minLat = double.infinity;
      var maxLat = -double.infinity;
      for (final point in ring) {
        minLng = math.min(minLng, point.dx);
        maxLng = math.max(maxLng, point.dx);
        minLat = math.min(minLat, point.dy);
        maxLat = math.max(maxLat, point.dy);
      }
      if (!minLng.isFinite || !minLat.isFinite) continue;
      final bounds = Rect.fromLTRB(minLng, minLat, maxLng, maxLat);
      final area = bounds.width.abs() * bounds.height.abs();
      if (area > bestArea) {
        bestArea = area;
        bestBounds = bounds;
      }
    }
  }

  return bestBounds?.center ?? Offset.zero;
}

class WorldGlobeCanvas extends StatefulWidget {
  const WorldGlobeCanvas({
    required this.shapes,
    required this.visitColorsByCode,
    required this.selectedCode,
    required this.centerLat,
    required this.centerLng,
    required this.zoom,
    required this.onChangedView,
    required this.onCountryTap,
    this.currentLocationLat,
    this.currentLocationLng,
    super.key,
  });

  final List<GlobeCountryShape> shapes;
  final Map<String, String> visitColorsByCode;
  final String? selectedCode;
  final double centerLat;
  final double centerLng;
  final double zoom;
  final double? currentLocationLat;
  final double? currentLocationLng;
  final void Function(double centerLat, double centerLng) onChangedView;
  final void Function(String code) onCountryTap;

  @override
  State<WorldGlobeCanvas> createState() => _WorldGlobeCanvasState();
}

class _WorldGlobeCanvasState extends State<WorldGlobeCanvas> {
  Offset? _lastLocal;

  @override
  Widget build(BuildContext context) {
    String? selectedName;
    for (final shape in widget.shapes) {
      if (shape.code == widget.selectedCode) {
        selectedName = shape.name;
        break;
      }
    }
    return Semantics(
      key: const ValueKey('world-map-canvas-semantics'),
      container: true,
      excludeSemantics: true,
      image: true,
      label:
          '세계 여행 지도 시각적 탐색용 캔버스. 전체 ${widget.shapes.length}개 국가 중 ${widget.visitColorsByCode.length}개 국가 방문.${selectedName == null ? '' : ' 선택한 국가 $selectedName.'}${widget.currentLocationLat == null ? '' : ' 현재 위치 표시 중.'}',
      hint: '지구본은 드래그하거나 확대해 탐색합니다. 화면 읽기 사용자는 장소 목록 열기 버튼으로 국가를 선택하세요.',
      child: GestureDetector(
        onPanStart: (details) => _lastLocal = details.localPosition,
        onPanUpdate: (details) {
          final last = _lastLocal;
          _lastLocal = details.localPosition;
          if (last == null) return;
          final delta = details.localPosition - last;
          final nextLng =
              _normalizeLng(widget.centerLng - delta.dx * 0.45 / widget.zoom);
          final nextLat = (widget.centerLat + delta.dy * 0.35 / widget.zoom)
              .clamp(-70.0, 70.0)
              .toDouble();
          widget.onChangedView(nextLat, nextLng);
        },
        onPanEnd: (_) => _lastLocal = null,
        onTapUp: (details) {
          final hit = _GlobeProjection.hitTest(
            size: context.size ?? Size.zero,
            tap: details.localPosition,
            shapes: widget.shapes,
            centerLat: widget.centerLat,
            centerLng: widget.centerLng,
            zoom: widget.zoom,
          );
          if (hit != null) widget.onCountryTap(hit);
        },
        child: CustomPaint(
          painter: _WorldGlobePainter(
            shapes: widget.shapes,
            visitColorsByCode: widget.visitColorsByCode,
            selectedCode: widget.selectedCode,
            centerLat: widget.centerLat,
            centerLng: widget.centerLng,
            zoom: widget.zoom,
            currentLocationLat: widget.currentLocationLat,
            currentLocationLng: widget.currentLocationLng,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  double _normalizeLng(double lng) {
    var v = lng;
    while (v > 180) {
      v -= 360;
    }
    while (v < -180) {
      v += 360;
    }
    return v;
  }
}

class _WorldGlobePainter extends CustomPainter {
  _WorldGlobePainter({
    required this.shapes,
    required this.visitColorsByCode,
    required this.selectedCode,
    required this.centerLat,
    required this.centerLng,
    required this.zoom,
    required this.currentLocationLat,
    required this.currentLocationLng,
  });

  final List<GlobeCountryShape> shapes;
  final Map<String, String> visitColorsByCode;
  final String? selectedCode;
  final double centerLat;
  final double centerLng;
  final double zoom;
  final double? currentLocationLat;
  final double? currentLocationLng;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.46 * zoom;
    final ocean = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.45),
        radius: 0.95,
        colors: [
          Color(0xFFE8F7FF),
          Color(0xFF94D2F5),
          Color(0xFF2F74B5),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, ocean);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.8),
    );

    _drawGraticule(canvas, size);

    final visible = <({GlobeCountryShape shape, Path path, Rect bounds})>[];
    for (final shape in shapes) {
      final path = _GlobeProjection.buildPath(
        shape: shape,
        size: size,
        centerLat: centerLat,
        centerLng: centerLng,
        zoom: zoom,
      );
      if (path == null) continue;
      visible.add((shape: shape, path: path, bounds: path.getBounds()));
    }

    for (final item in visible) {
      final color = _colorFromHex(visitColorsByCode[item.shape.code]) ??
          const Color(0xFFF8F2DF);
      canvas.drawPath(item.path, Paint()..color = color);
      canvas.drawPath(
        item.path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selectedCode == item.shape.code ? 2.4 : 0.75
          ..color = selectedCode == item.shape.code
              ? const Color(0xFFE678A9)
              : const Color(0xFF365267).withValues(alpha: 0.62),
      );
    }

    _drawCountryLabels(canvas, size, visible);

    canvas.drawCircle(
      center.translate(-radius * 0.2, -radius * 0.25),
      radius * 0.95,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white.withValues(alpha: 0.24), Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    final latitude = currentLocationLat;
    final longitude = currentLocationLng;
    if (latitude != null && longitude != null) {
      final point = _GlobeProjection.project(
        lngLat: Offset(longitude, latitude),
        size: size,
        centerLat: centerLat,
        centerLng: centerLng,
        zoom: zoom,
      );
      if (point != null) {
        canvas.drawCircle(
          point,
          12,
          Paint()..color = const Color(0xFF3478F6).withValues(alpha: 0.22),
        );
        canvas.drawCircle(point, 7, Paint()..color = Colors.white);
        canvas.drawCircle(
          point,
          4.5,
          Paint()..color = const Color(0xFF3478F6),
        );
      }
    }
  }

  void _drawGraticule(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..color = Colors.white.withValues(alpha: 0.34);

    for (var lat = -60; lat <= 60; lat += 30) {
      final path = Path();
      var started = false;
      for (var lng = -180; lng <= 180; lng += 4) {
        final p = _GlobeProjection.project(
          lngLat: Offset(lng.toDouble(), lat.toDouble()),
          size: size,
          centerLat: centerLat,
          centerLng: centerLng,
          zoom: zoom,
        );
        if (p == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    for (var lng = -180; lng < 180; lng += 30) {
      final path = Path();
      var started = false;
      for (var lat = -80; lat <= 80; lat += 4) {
        final p = _GlobeProjection.project(
          lngLat: Offset(lng.toDouble(), lat.toDouble()),
          size: size,
          centerLat: centerLat,
          centerLng: centerLng,
          zoom: zoom,
        );
        if (p == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  void _drawCountryLabels(
    Canvas canvas,
    Size size,
    List<({GlobeCountryShape shape, Path path, Rect bounds})> visible,
  ) {
    for (final item in visible) {
      final bounds = item.bounds;
      if (bounds.width < 26 || bounds.height < 12) continue;

      final fontSize = (7.5 + (zoom * 1.8)).clamp(7.5, 11.0).toDouble();
      final textPainter = TextPainter(
        text: TextSpan(
          text: item.shape.name,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF243447).withValues(
                alpha: selectedCode == item.shape.code ? 0.95 : 0.78),
            shadows: const [
              Shadow(color: Colors.white, blurRadius: 3),
              Shadow(color: Colors.white, blurRadius: 6),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: bounds.width);

      // 국가 영역보다 글씨가 크면 숨김: 작은 섬/소국의 과밀 라벨 방지.
      if (textPainter.width > bounds.width * 0.72 ||
          textPainter.height > bounds.height * 0.55) {
        continue;
      }

      final labelCenter = _GlobeProjection.project(
        lngLat: item.shape.labelLngLat,
        size: size,
        centerLat: centerLat,
        centerLng: centerLng,
        zoom: zoom,
      );
      if (labelCenter == null || !item.path.contains(labelCenter)) continue;

      final offset = Offset(
        labelCenter.dx - textPainter.width / 2,
        labelCenter.dy - textPainter.height / 2,
      );
      canvas.save();
      canvas.clipPath(item.path);
      textPainter.paint(canvas, offset);
      canvas.restore();
    }
  }

  Color? _colorFromHex(String? hex) {
    if (hex == null) return null;
    final normalized = hex.replaceAll('#', '');
    if (normalized.length != 6) return null;
    return Color(int.parse('FF$normalized', radix: 16));
  }

  @override
  bool shouldRepaint(covariant _WorldGlobePainter oldDelegate) => true;
}

class _GlobeProjection {
  static Offset? project({
    required Offset lngLat,
    required Size size,
    required double centerLat,
    required double centerLng,
    required double zoom,
  }) {
    final radius = math.min(size.width, size.height) * 0.46 * zoom;
    final center = size.center(Offset.zero);
    final lat = _rad(lngLat.dy);
    final lng = _rad(lngLat.dx);
    final lat0 = _rad(centerLat);
    final lng0 = _rad(centerLng);
    final cosc = math.sin(lat0) * math.sin(lat) +
        math.cos(lat0) * math.cos(lat) * math.cos(lng - lng0);
    if (cosc <= -0.04) return null;
    final x = radius * math.cos(lat) * math.sin(lng - lng0);
    final y = -radius *
        (math.cos(lat0) * math.sin(lat) -
            math.sin(lat0) * math.cos(lat) * math.cos(lng - lng0));
    return center + Offset(x, y);
  }

  static Path? buildPath({
    required GlobeCountryShape shape,
    required Size size,
    required double centerLat,
    required double centerLng,
    required double zoom,
  }) {
    final path = Path();
    var hasAny = false;
    for (final polygon in shape.polygons) {
      for (final ring in polygon) {
        var started = false;
        for (final point in ring) {
          final projected = project(
            lngLat: point,
            size: size,
            centerLat: centerLat,
            centerLng: centerLng,
            zoom: zoom,
          );
          if (projected == null) {
            started = false;
            continue;
          }
          if (!started) {
            path.moveTo(projected.dx, projected.dy);
            started = true;
            hasAny = true;
          } else {
            path.lineTo(projected.dx, projected.dy);
          }
        }
        if (started) path.close();
      }
    }
    return hasAny ? path : null;
  }

  static String? hitTest({
    required Size size,
    required Offset tap,
    required List<GlobeCountryShape> shapes,
    required double centerLat,
    required double centerLng,
    required double zoom,
  }) {
    if (size == Size.zero) return null;
    for (final shape in shapes.reversed) {
      final path = buildPath(
        shape: shape,
        size: size,
        centerLat: centerLat,
        centerLng: centerLng,
        zoom: zoom,
      );
      if (path != null && path.contains(tap)) return shape.code;
    }
    return null;
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
