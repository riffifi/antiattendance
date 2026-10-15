import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'campus_map_data.dart';
import 'floor_georeference.dart';
import 'indoor_route_planner.dart';
import '../l10n.dart';
import '../editorial_controls.dart';

class CampusMapCanvas extends StatefulWidget {
  const CampusMapCanvas({
    super.key,
    required this.floor,
    required this.places,
    required this.onPlace,
    this.selected,
    this.start,
    this.route,
    this.position,
    this.accuracyMeters,
    this.locationFocus = 0,
    this.kind,
    this.favorites = const {},
  });
  final CampusFloor floor;
  final List<CampusPlace> places;
  final ValueChanged<CampusPlace> onPlace;
  final CampusPlace? selected, start;
  final IndoorRoute? route;
  final FloorPoint? position;
  final double? accuracyMeters;
  final int locationFocus;
  final String? kind;
  final Set<String> favorites;
  @override
  State<CampusMapCanvas> createState() => _CampusMapCanvasState();
}

class _CampusMapCanvasState extends State<CampusMapCanvas> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;
  bool _reset = true;
  bool _focusPosition = false;
  double get _fit => math.min(
    _viewport.width / widget.floor.width,
    _viewport.height / widget.floor.height,
  );
  @override
  void didUpdateWidget(CampusMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locationFocus != widget.locationFocus) {
      _reset = true;
      _focusPosition = true;
    }
    if (oldWidget.floor.id != widget.floor.id ||
        oldWidget.selected?.id != widget.selected?.id ||
        oldWidget.route != widget.route) {
      _reset = true;
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _center(double x, double y, double scale) {
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, _viewport.width / 2 - x * scale)
      ..setEntry(1, 3, _viewport.height / 2 - y * scale);
  }

  void _focus() {
    if (widget.position case final point? when _focusPosition) {
      _focusPosition = false;
      _center(point.x, point.y, _fit * 4);
      return;
    }
    final segments =
        widget.route?.segmentsForFloor(widget.floor.id).toList() ?? [];
    final nodes = segments.expand((s) => s.nodes).toList();
    if (nodes.isNotEmpty) {
      final xs = nodes.map((n) => n.x), ys = nodes.map((n) => n.y);
      final minX = xs.reduce(math.min),
          maxX = xs.reduce(math.max),
          minY = ys.reduce(math.min),
          maxY = ys.reduce(math.max);
      final scale = math
          .min(
            _viewport.width / (maxX - minX + 140),
            _viewport.height / (maxY - minY + 140),
          )
          .clamp(_fit, _fit * 12);
      _center((minX + maxX) / 2, (minY + maxY) / 2, scale);
    } else if (widget.selected case final place?
        when place.floorId == widget.floor.id) {
      _center(place.x, place.y, _fit * 4);
    } else {
      _center(widget.floor.width / 2, widget.floor.height / 2, _fit);
    }
  }

  void _zoom(double factor) {
    final point = _transform.toScene(
      Offset(_viewport.width / 2, _viewport.height / 2),
    );
    _center(
      point.dx,
      point.dy,
      (_transform.value.getMaxScaleOnAxis() * factor).clamp(
        _fit * .5,
        _fit * 20,
      ),
    );
  }

  void _tap(TapUpDetails details) {
    final point = details.localPosition;
    for (final place in widget.places) {
      if (widget.kind != null && place.kind != widget.kind) continue;
      if (widget.floor.paths[place.id]?.contains(point) == true) {
        widget.onPlace(place);
        return;
      }
    }
    CampusPlace? nearest;
    var distance = 26 / _transform.value.getMaxScaleOnAxis();
    for (final place in widget.places) {
      if (widget.kind != null && place.kind != widget.kind) continue;
      final d = (Offset(place.x, place.y) - point).distance;
      if (d < distance) {
        nearest = place;
        distance = d;
      }
    }
    if (nearest != null) widget.onPlace(nearest);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (size.shortestSide <= 0) return const SizedBox.shrink();
      if (_viewport != size) {
        _viewport = size;
        _reset = true;
      }
      if (_reset) {
        _reset = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focus();
        });
      }
      return ClipRect(
        child: Stack(
          children: [
            ColoredBox(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.surface
                  : const Color(0xFFF9FBFE),
              child: InteractiveViewer(
                transformationController: _transform,
                constrained: false,
                boundaryMargin: EdgeInsets.all(widget.floor.width),
                minScale: _fit * .5,
                maxScale: _fit * 20,
                child: GestureDetector(
                  onTapUp: _tap,
                  child: SizedBox(
                    width: widget.floor.width,
                    height: widget.floor.height,
                    child: Stack(
                      children: [
                        SvgPicture.string(
                          widget.floor.svg,
                          width: widget.floor.width,
                          height: widget.floor.height,
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _MapPainter(
                                transform: _transform,
                                viewport: _viewport,
                                floor: widget.floor,
                                places: widget.places,
                                selected: widget.selected,
                                start: widget.start,
                                route: widget.route,
                                position: widget.position,
                                accuracyMeters: widget.accuracyMeters,
                                kind: widget.kind,
                                favorites: widget.favorites,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CampusTextAction(
                      onPressed: () => _zoom(1.5),
                      tooltip: tr(context, 'Приблизить', 'Zoom in'),
                      label: tr(context, 'Приблизить', 'Zoom in'),
                    ),
                    CampusTextAction(
                      onPressed: () => _zoom(1 / 1.5),
                      tooltip: tr(context, 'Отдалить', 'Zoom out'),
                      label: tr(context, 'Отдалить', 'Zoom out'),
                    ),
                    CampusTextAction(
                      onPressed: _focus,
                      tooltip: tr(context, 'Показать на карте', 'Focus map'),
                      label: tr(context, 'Показать на карте', 'Focus map'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.transform,
    required this.viewport,
    required this.floor,
    required this.places,
    required this.favorites,
    this.selected,
    this.start,
    this.route,
    this.position,
    this.accuracyMeters,
    this.kind,
  }) : super(repaint: transform);
  final TransformationController transform;
  final Size viewport;
  final CampusFloor floor;
  final List<CampusPlace> places;
  final CampusPlace? selected, start;
  final IndoorRoute? route;
  final FloorPoint? position;
  final double? accuracyMeters;
  final String? kind;
  final Set<String> favorites;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = transform.value.getMaxScaleOnAxis();
    final line = Paint()
      ..color = const Color(0xFF6750A4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 / scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final segment
        in route?.segmentsForFloor(floor.id) ?? <IndoorRouteFloorSegment>[]) {
      if (segment.nodes.isEmpty) continue;
      final path = Path()..moveTo(segment.nodes.first.x, segment.nodes.first.y);
      for (final n in segment.nodes.skip(1)) {
        path.lineTo(n.x, n.y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8 / scale,
      );
      canvas.drawPath(path, line);
    }
    final shownLabels = <Rect>[];
    final bounds = Rect.fromPoints(
      transform.toScene(Offset.zero),
      transform.toScene(Offset(viewport.width, viewport.height)),
    );
    for (final place in places) {
      final chosen = place.id == selected?.id || place.id == start?.id;
      if (kind != null && place.kind != kind && !chosen) continue;
      final tagged = kind == null ? place.kind != 'room' : place.kind == kind;
      if (!chosen && !tagged && !favorites.contains(place.id) && scale < .8) {
        continue;
      }
      final point = Offset(place.x, place.y);
      if (floor.paths[place.id] case final path? when chosen) {
        canvas.drawPath(
          path,
          Paint()
            ..color = colorForPlace(place.id == start?.id)
                .withValues(alpha: .22),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = colorForPlace(place.id == start?.id)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / scale,
        );
      }
      if (!bounds.inflate(100 / scale).contains(point) && !chosen) continue;
      final color = place.id == start?.id
          ? const Color(0xFF2E7D32)
          : chosen
          ? const Color(0xFFE65100)
          : place.kind == 'toilet'
          ? const Color(0xFF1565C0)
          : place.kind == 'cafeteria'
          ? const Color(0xFFAD1457)
          : const Color(0xFF6750A4);
      canvas.drawCircle(
        point,
        (chosen ? 7 : 4) / scale,
        Paint()..color = color,
      );
      final text = TextPainter(
        text: TextSpan(
          text: place.label,
          style: TextStyle(
            fontSize: 12 / scale,
            fontFamily: 'Geist',
            color: color,
            fontWeight: chosen ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 150 / scale);
      final label = Rect.fromLTWH(
        point.dx + 8 / scale,
        point.dy - text.height / 2,
        text.width,
        text.height,
      ).inflate(2 / scale);
      if (!chosen && shownLabels.any((r) => r.overlaps(label))) continue;
      shownLabels.add(label);
      canvas.drawRRect(
        RRect.fromRectAndRadius(label, Radius.circular(4 / scale)),
        Paint()..color = Colors.white.withValues(alpha: .92),
      );
      text.paint(canvas, Offset(label.left + 2 / scale, label.top + 2 / scale));
    }
    if (position case final p?) {
      final center = Offset(p.x, p.y);
      final radius = (accuracyMeters ?? 0) / floor.metersPerUnit;
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0xFF1976D2).withValues(alpha: .13),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xFF1976D2).withValues(alpha: .4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
      canvas.drawCircle(center, 8 / scale, Paint()..color = Colors.white);
      canvas.drawCircle(
        center,
        6 / scale,
        Paint()..color = const Color(0xFF1976D2),
      );
    }
  }

  Color colorForPlace(bool start) =>
      start ? const Color(0xFF2E7D32) : const Color(0xFFE65100);

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}
