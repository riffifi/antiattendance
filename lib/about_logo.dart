import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'campus_design.dart';
import 'l10n.dart';

/// A rigid badge that returns to its resting pose after direct manipulation.
class AboutLogo extends StatefulWidget {
  const AboutLogo({super.key});
  @override
  State<AboutLogo> createState() => _AboutLogoState();
}

class _AboutLogoState extends State<AboutLogo>
    with SingleTickerProviderStateMixin {
  double _yaw = 0;
  double _pitch = 0;
  late final AnimationController _spring;
  double _releaseYaw = 0;
  double _releasePitch = 0;
  bool _focused = false;
  bool _portraitBack = false;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() {
          _yaw = _releaseYaw * _spring.value;
          _pitch = _releasePitch * _spring.value;
        });
      });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _settle() {
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() {
        _yaw = 0;
        _pitch = 0;
      });
      return;
    }
    _releaseYaw = _yaw;
    _releasePitch = _pitch;
    _spring.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 180, damping: 22),
        1,
        0,
        0,
      ),
    );
  }

  void _nudge(double yaw) {
    _spring.stop();
    _rotate(yaw);
    _settle();
  }

  void _rotate(double yaw, [double pitch = 0]) => setState(() {
    final wasBack = math.cos(_yaw) < 0;
    _yaw = (_yaw + yaw).clamp(-math.pi, math.pi);
    // Select a face on entry, so reversing a drag while behind does not swap it.
    if (!wasBack && math.cos(_yaw) < 0) {
      _portraitBack = yaw < 0;
    }
    _pitch = (_pitch + pitch).clamp(-.3, .3);
  });

  @override
  Widget build(BuildContext context) {
    final back = math.cos(_yaw) < 0;
    final palette = context.palette;
    final rotation = Matrix4.identity()
      ..setEntry(3, 2, .0008)
      ..rotateX(_pitch)
      ..rotateY(_yaw);
    final face = Color.lerp(
      palette.surface,
      Theme.of(context).colorScheme.surfaceContainerHigh,
      .12,
    )!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: tr(context, 'Логотип приложения', 'App logo'),
          value: back
              ? (_portraitBack
                    ? 'Станислав Кудж'
                    : tr(context, 'Прежний логотип', 'Original logo'))
              : 'aa.',
          onTap: () => _nudge(math.pi),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _nudge(-.35),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _nudge(.35),
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  _nudge(math.pi),
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  _nudge(math.pi),
            },
            child: FocusableActionDetector(
              mouseCursor: SystemMouseCursors.grab,
              onShowFocusHighlight: (value) => setState(() => _focused = value),
              child: GestureDetector(
                key: const ValueKey('about-logo-rotation'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () => _nudge(math.pi),
                onPanStart: (_) => _spring.stop(),
                onPanEnd: (_) => _settle(),
                onPanCancel: _settle,
                onPanUpdate: (details) =>
                    _rotate(details.delta.dx * .018, -details.delta.dy * .008),
                child: SizedBox(
                  width: 240,
                  height: 208,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 144,
                        height: 144,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                key: const ValueKey('about-logo-solid-body'),
                                painter: _BadgeBodyPainter(
                                  rotation: rotation,
                                  color: Color.lerp(
                                    palette.line,
                                    palette.ink,
                                    .18,
                                  )!,
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Transform(
                                alignment: Alignment.center,
                                key: const ValueKey(
                                  'about-logo-face-transform',
                                ),
                                transform: rotation.clone()
                                  ..translateByDouble(0, 0, back ? -3 : 3, 1)
                                  ..rotateY(back ? math.pi : 0),
                                child: Container(
                                  key: ValueKey(
                                    back
                                        ? 'about-logo-back'
                                        : 'about-logo-front',
                                  ),
                                  padding: EdgeInsets.all(
                                    back ? (_portraitBack ? 0 : 18) : 22,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: back ? Colors.white : face,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: _focused
                                          ? palette.blue
                                          : palette.line,
                                      width: _focused ? 2 : 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: back
                                        ? (_portraitBack
                                              ? Image.asset(
                                                  'assets/about/stanislav_kudzh.jpg',
                                                  key: const ValueKey(
                                                    'about-logo-portrait',
                                                  ),
                                                  width: 144,
                                                  height: 144,
                                                  fit: BoxFit.cover,
                                                  alignment:
                                                      Alignment.topCenter,
                                                  semanticLabel:
                                                      'Станислав Кудж',
                                                )
                                              : SvgPicture.asset(
                                                  'icon/legacy_brand.svg',
                                                  width: 108,
                                                  height: 108,
                                                  semanticsLabel: tr(
                                                    context,
                                                    'Прежний логотип',
                                                    'Original logo',
                                                  ),
                                                ))
                                        : const CampusBrand(
                                            width: 100,
                                            height: 48,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Projects the silhouette of a rounded extrusion as one filled shape. The
/// visible face is painted above it; there are no intermediate plates or seams.
class _BadgeBodyPainter extends CustomPainter {
  const _BadgeBodyPainter({required this.rotation, required this.color});

  final Matrix4 rotation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const radius = 30.0;
    final halfWidth = size.width / 2;
    final halfHeight = size.height / 2;
    final points = <Offset>[];
    final matrix = rotation.storage;
    for (final depth in [-3.0, 3.0]) {
      for (var corner = 0; corner < 4; corner++) {
        final cx = (corner == 0 || corner == 3 ? 1 : -1) * (halfWidth - radius);
        final cy = (corner < 2 ? 1 : -1) * (halfHeight - radius);
        for (var step = 0; step <= 16; step++) {
          final angle = (corner + step / 16) * math.pi / 2;
          final x = cx + radius * math.cos(angle);
          final y = cy + radius * math.sin(angle);
          final w =
              matrix[3] * x + matrix[7] * y + matrix[11] * depth + matrix[15];
          points.add(
            center +
                Offset(
                  (matrix[0] * x +
                          matrix[4] * y +
                          matrix[8] * depth +
                          matrix[12]) /
                      w,
                  (matrix[1] * x +
                          matrix[5] * y +
                          matrix[9] * depth +
                          matrix[13]) /
                      w,
                ),
          );
        }
      }
    }
    // Both rounded faces bound a convex solid. Their projected convex hull
    // includes the continuous side wall even when the face is exactly edge-on.
    points.sort((a, b) {
      final byX = a.dx.compareTo(b.dx);
      return byX == 0 ? a.dy.compareTo(b.dy) : byX;
    });
    double cross(Offset a, Offset b, Offset c) =>
        (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    List<Offset> boundary(Iterable<Offset> ordered) {
      final edge = <Offset>[];
      for (final point in ordered) {
        while (edge.length >= 2 &&
            cross(edge[edge.length - 2], edge.last, point) <= 0) {
          edge.removeLast();
        }
        edge.add(point);
      }
      return edge..removeLast();
    }

    final hull = [...boundary(points), ...boundary(points.reversed)];
    canvas.drawPath(Path()..addPolygon(hull, true), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BadgeBodyPainter oldDelegate) =>
      rotation != oldDelegate.rotation || color != oldDelegate.color;
}
