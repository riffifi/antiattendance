import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'app_theme.dart';
import 'campus_design.dart';
import 'l10n.dart';

/// One reversible face, directly manipulated vertically, then sprung home.
class AboutLogo extends StatefulWidget {
  const AboutLogo({
    super.key,
    this.size = 144,
    this.reserveRotationSpace = true,
  });
  final double size;
  final bool reserveRotationSpace;
  @override
  State<AboutLogo> createState() => _AboutLogoState();
}

class _AboutLogoState extends State<AboutLogo>
    with SingleTickerProviderStateMixin {
  double _angle = 0, _release = 0;
  bool _portraitBack = false, _focused = false;
  late final AnimationController _spring;
  @override
  void initState() {
    super.initState();
    _spring = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() => _angle = _release * _spring.value));
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _rotate(double delta) => setState(() {
    final wasBack = math.cos(_angle) < 0;
    _angle = (_angle + delta).clamp(-math.pi, math.pi);
    if (!wasBack && math.cos(_angle) < 0) _portraitBack = delta < 0;
  });
  void _settle() {
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _angle = 0);
      return;
    }
    _release = _angle;
    _spring.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 180, damping: 22),
        1,
        0,
        0,
      ),
    );
  }

  void _nudge(double delta) {
    _spring.stop();
    _rotate(delta);
    _settle();
  }

  @override
  Widget build(BuildContext context) {
    final back = math.cos(_angle) < 0;
    final p = context.palette;
    final transform = Matrix4.identity()
      ..setEntry(3, 2, .0008)
      ..rotateX(_angle)
      ..rotateX(back ? math.pi : 0);
    return Semantics(
      button: true,
      label: tr(context, 'Логотип приложения', 'App logo'),
      value: back
          ? _portraitBack
                ? 'Станислав Кудж'
                : tr(context, 'Прежний логотип', 'Original logo')
          : 'aa.',
      onTap: () => _nudge(math.pi),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _nudge(-math.pi),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _nudge(math.pi),
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
            onVerticalDragStart: (_) => _spring.stop(),
            onVerticalDragUpdate: (event) =>
                _rotate(event.delta.dy * math.pi / (widget.size * .8)),
            onVerticalDragEnd: (_) => _settle(),
            onVerticalDragCancel: _settle,
            child: SizedBox(
              width: widget.reserveRotationSpace
                  ? widget.size * 5 / 3
                  : widget.size,
              height: widget.reserveRotationSpace
                  ? widget.size * 13 / 9
                  : widget.size,
              child: Center(
                child: Transform(
                  key: const ValueKey('about-logo-face-transform'),
                  transform: transform,
                  alignment: Alignment.center,
                  child: Container(
                    key: ValueKey(
                      back ? 'about-logo-back' : 'about-logo-front',
                    ),
                    width: widget.size,
                    height: widget.size,
                    padding: EdgeInsets.all(
                      (back
                              ? _portraitBack
                                    ? 0
                                    : 18
                              : 22) *
                          widget.size /
                          144,
                    ),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: back ? Colors.white : p.surface,
                      border: Border.all(
                        color: _focused ? p.blue : p.line,
                        width: _focused ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: back
                          ? _portraitBack
                                ? Image.asset(
                                    'assets/about/stanislav_kudzh.jpg',
                                    key: const ValueKey('about-logo-portrait'),
                                    width: widget.size,
                                    height: widget.size,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                    semanticLabel: 'Станислав Кудж',
                                  )
                                : SvgPicture.asset(
                                    'icon/legacy_brand.svg',
                                    width: widget.size * .75,
                                    height: widget.size * .75,
                                    semanticsLabel: tr(
                                      context,
                                      'Прежний логотип',
                                      'Original logo',
                                    ),
                                  )
                          : CampusBrand(width: widget.size * 100 / 144),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
