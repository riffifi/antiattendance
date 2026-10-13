import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'campus_design.dart';
import 'l10n.dart';

/// Direct manipulation of a solid, two-sided badge. No spring or auto-spin.
class AboutLogo extends StatefulWidget {
  const AboutLogo({super.key});
  @override
  State<AboutLogo> createState() => _AboutLogoState();
}

class _AboutLogoState extends State<AboutLogo> {
  double _yaw = 0;
  double _pitch = -.12;
  bool _focused = false;

  void _rotate(double yaw, [double pitch = 0]) => setState(() {
    _yaw = (_yaw + yaw) % (2 * math.pi);
    _pitch = (_pitch + pitch).clamp(-.45, .45);
  });

  @override
  Widget build(BuildContext context) {
    final back = math.cos(_yaw) < 0;
    final palette = context.palette;
    final rotation = Matrix4.identity()
      ..setEntry(3, 2, .0018)
      ..rotateX(_pitch)
      ..rotateY(_yaw);
    final face = Color.lerp(
      palette.surface,
      Theme.of(context).colorScheme.surfaceContainerHigh,
      .12,
    )!;
    final depths = back
        ? [6.0, 3.0, 0.0, -3.0, -6.0]
        : [-6.0, -3.0, 0.0, 3.0, 6.0];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: tr(context, 'Логотип приложения', 'App logo'),
          value: back ? tr(context, 'Прежний логотип', 'Original logo') : 'aa.',
          hint: tr(
            context,
            'Перетащите, чтобы повернуть. Нажмите, чтобы перевернуть.',
            'Drag to rotate. Tap to flip.',
          ),
          onTap: () => _rotate(math.pi),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _rotate(-.35),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _rotate(.35),
              const SingleActivator(LogicalKeyboardKey.enter): () =>
                  _rotate(math.pi),
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  _rotate(math.pi),
            },
            child: FocusableActionDetector(
              mouseCursor: SystemMouseCursors.grab,
              onShowFocusHighlight: (value) => setState(() => _focused = value),
              child: GestureDetector(
                key: const ValueKey('about-logo-rotation'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: () => _rotate(math.pi),
                onPanUpdate: (details) =>
                    _rotate(details.delta.dx * .018, -details.delta.dy * .008),
                child: SizedBox(
                  width: 240,
                  height: 208,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // A cast shadow sits below the object, rather than emitting light.
                      Positioned(
                        bottom: 26,
                        child: Transform.scale(
                          scaleX: .65 + .35 * math.cos(_yaw).abs(),
                          child: Container(
                            width: 136,
                            height: 14,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? .4
                                        : .16,
                                  ),
                                  blurRadius: 22,
                                  spreadRadius: 4,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Transform(
                        alignment: Alignment.center,
                        transform: rotation,
                        child: SizedBox(
                          width: 144,
                          height: 144,
                          child: Stack(
                            children: [
                              for (final depth in depths)
                                Positioned.fill(
                                  child: Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.translationValues(
                                      0,
                                      0,
                                      depth,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Color.lerp(
                                          palette.line,
                                          palette.ink,
                                          .12,
                                        ),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned.fill(
                                child: Transform(
                                  alignment: Alignment.center,
                                  transform: back
                                      ? (Matrix4.translationValues(0, 0, -6)
                                          ..rotateY(math.pi))
                                      : Matrix4.translationValues(0, 0, 6),
                                  child: Container(
                                    key: ValueKey(
                                      back
                                          ? 'about-logo-back'
                                          : 'about-logo-front',
                                    ),
                                    padding: EdgeInsets.all(back ? 18 : 22),
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
                                          ? SvgPicture.asset(
                                              'icon/legacy_brand.svg',
                                              width: 108,
                                              height: 108,
                                              semanticsLabel: tr(
                                                context,
                                                'Прежний логотип',
                                                'Original logo',
                                              ),
                                            )
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Text(
          tr(context, 'Перетащите, чтобы повернуть', 'Drag to rotate'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
