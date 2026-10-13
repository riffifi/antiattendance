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
  bool _portraitBack = false;

  void _rotate(double yaw, [double pitch = 0]) => setState(() {
    final wasBack = math.cos(_yaw) < 0;
    _yaw = (_yaw + yaw) % (2 * math.pi);
    // Select a face on entry, so reversing a drag while behind does not swap it.
    if (!wasBack && math.cos(_yaw) < 0) {
      _portraitBack = yaw < 0;
    }
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
          value: back
              ? (_portraitBack
                    ? 'Станислав Кудж'
                    : tr(context, 'Прежний логотип', 'Original logo'))
              : 'aa.',
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
