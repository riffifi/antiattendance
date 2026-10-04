import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Maps camera coordinates through the same centered BoxFit.cover as the preview.
List<Offset> projectQrCorners(
  List<Offset> corners,
  Size source,
  Size viewport,
) {
  if (corners.length != 4 ||
      source.isEmpty ||
      viewport.isEmpty ||
      corners.any((point) => !point.dx.isFinite || !point.dy.isFinite)) {
    return [];
  }
  final scale = math.max(
    viewport.width / source.width,
    viewport.height / source.height,
  );
  final crop = Offset(
    (source.width * scale - viewport.width) / 2,
    (source.height * scale - viewport.height) / 2,
  );
  final points = corners.map((point) => point * scale - crop).toList();
  final center = points.reduce((a, b) => a + b) / 4;
  points.sort(
    (a, b) => math
        .atan2(a.dy - center.dy, a.dx - center.dx)
        .compareTo(math.atan2(b.dy - center.dy, b.dx - center.dx)),
  );
  var first = 0;
  for (var i = 1; i < 4; i++) {
    if (points[i].dx + points[i].dy < points[first].dx + points[first].dy) {
      first = i;
    }
  }
  return [for (var i = 0; i < 4; i++) points[(first + i) % 4]];
}

class QrFrameTracker extends ChangeNotifier {
  List<Offset> corners = [];
  Size source = Size.zero;
  Timer? _reset;
  void detect(List<Offset> points, Size imageSize) {
    if (points.length != 4 || imageSize.isEmpty) return;
    corners = points;
    source = imageSize;
    _reset?.cancel();
    notifyListeners();
    _reset = Timer(const Duration(milliseconds: 1100), () {
      corners = [];
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }
}

/// Animates the four corners independently, including perspective and rotation.
class QrTrackingOverlay extends StatefulWidget {
  const QrTrackingOverlay({
    super.key,
    required this.tracker,
    required this.color,
    this.fallbackKey,
    this.fallbackSize = 250,
  });
  final QrFrameTracker tracker;
  final Color color;
  final GlobalKey? fallbackKey;
  final double fallbackSize;
  @override
  State<QrTrackingOverlay> createState() => _QrTrackingOverlayState();
}

class _QrTrackingOverlayState extends State<QrTrackingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Size _viewport = Size.zero;
  List<Offset> _from = [], _to = [];
  Rect? _fallbackRect;
  @override
  void initState() {
    super.initState();
    widget.tracker.addListener(_changed);
  }

  @override
  void didUpdateWidget(QrTrackingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracker != widget.tracker) {
      oldWidget.tracker.removeListener(_changed);
      widget.tracker.addListener(_changed);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
  }

  List<Offset> get _fallback {
    final side = math.min(
      widget.fallbackSize,
      math.min(_viewport.width, _viewport.height) * .7,
    );
    final rect =
        _fallbackRect ??
        Rect.fromCenter(
          center: _viewport.center(Offset.zero),
          width: side,
          height: side,
        );
    return [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
  }

  List<Offset> get _current => _to.isEmpty
      ? _fallback
      : [
          for (var i = 0; i < 4; i++)
            Offset.lerp(
              _from[i],
              _to[i],
              Curves.easeOutCubic.transform(_motion.value),
            )!,
        ];
  void _changed() {
    if (!mounted || _viewport.isEmpty) return;
    _from = _current;
    final projected = projectQrCorners(
      widget.tracker.corners,
      widget.tracker.source,
      _viewport,
    );
    _to = projected.isEmpty ? _fallback : projected;
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    widget.tracker.removeListener(_changed);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        _viewport = constraints.biggest;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || widget.fallbackKey == null) return;
          final frame = widget.fallbackKey!.currentContext?.findRenderObject();
          final overlay = this.context.findRenderObject();
          if (frame is RenderBox && overlay is RenderBox) {
            final rect =
                (frame.localToGlobal(Offset.zero) -
                    overlay.localToGlobal(Offset.zero)) &
                frame.size;
            if (rect != _fallbackRect) {
              _fallbackRect = rect;
              if (widget.tracker.corners.isEmpty) _changed();
            }
          }
        });
        return AnimatedBuilder(
          animation: _motion,
          builder: (_, _) => CustomPaint(
            painter: _QrCorners(_current, widget.color),
            size: constraints.biggest,
          ),
        );
      },
    ),
  );
}

class _QrCorners extends CustomPainter {
  const _QrCorners(this.points, this.color);
  final List<Offset> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .3)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final pen = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final corner = points[i];
      final previous = Offset.lerp(corner, points[(i + 3) % 4], .18)!;
      final next = Offset.lerp(corner, points[(i + 1) % 4], .18)!;
      final path = Path()
        ..moveTo(previous.dx, previous.dy)
        ..lineTo(corner.dx, corner.dy)
        ..lineTo(next.dx, next.dy);
      canvas.drawPath(path, shadow);
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(_QrCorners old) =>
      old.color != color || old.points != points;
}
