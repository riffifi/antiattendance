import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'theme.dart';
import 'feedback.dart';
import 'motion.dart';

const brockmannEaseOut = brockmannOutExpo;
const brockmannEaseInOut = brockmannInOut;

/// Shared tap, keyboard, focus and TalkBack behavior without a Material ripple.
class BrockmannPressable extends StatefulWidget {
  const BrockmannPressable({
    super.key,
    required this.label,
    required this.builder,
    this.onPressed,
    this.sound,
    this.selected,
    this.toggled,
    this.button = true,
    this.tooltip,
    this.tiltStrength = 0,
    this.onKey,
    this.excludeSemantics = true,
  });
  final String label;
  final Widget Function(BuildContext, bool) builder;
  final VoidCallback? onPressed;
  final BrockmannSound? sound;
  final bool? selected, toggled;
  final bool button;
  final bool excludeSemantics;
  final String? tooltip;
  final double tiltStrength;
  final ValueChanged<LogicalKeyboardKey>? onKey;
  @override
  State<BrockmannPressable> createState() => _BrockmannPressableState();
}

class _BrockmannPressableState extends State<BrockmannPressable> {
  bool pressed = false, focused = false;
  Offset _point = Offset.zero;
  void _invoke() {
    if (widget.onPressed == null) return;
    if (widget.sound != null) {
      BrockmannFeedbackScope.play(context, widget.sound!);
    }
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    Widget child = Semantics(
      label: widget.label,
      button: widget.button,
      enabled: widget.onPressed != null,
      selected: widget.selected,
      toggled: widget.toggled,
      onTap: widget.onPressed == null ? null : _invoke,
      excludeSemantics: widget.excludeSemantics,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        onShowFocusHighlight: (v) => setState(() => focused = v),
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(LogicalKeyboardKey.space):
              const ActivateIntent(),
          if (widget.onKey != null)
            for (final key in [
              LogicalKeyboardKey.arrowLeft,
              LogicalKeyboardKey.arrowRight,
              LogicalKeyboardKey.arrowUp,
              LogicalKeyboardKey.arrowDown,
              LogicalKeyboardKey.home,
              LogicalKeyboardKey.end,
            ])
              SingleActivator(key): _ControlKeyIntent(key),
        },
        actions: {
          _ControlKeyIntent: CallbackAction<_ControlKeyIntent>(
            onInvoke: (intent) {
              widget.onKey?.call(intent.key);
              return null;
            },
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _invoke();
              return null;
            },
          ),
        },
        child: Listener(
          onPointerDown: widget.onPressed == null
              ? null
              : (event) {
                  final size = context.size ?? const Size(200, 48);
                  setState(() {
                    pressed = true;
                    _point = Offset(
                      ((event.localPosition.dx - size.width / 2) /
                              math.max(1, size.width / 2))
                          .clamp(-1, 1),
                      ((event.localPosition.dy - size.height / 2) /
                              math.max(1, size.height / 2))
                          .clamp(-1, 1),
                    );
                  });
                },
          onPointerUp: (_) {
            if (pressed) setState(() => pressed = false);
          },
          onPointerCancel: (_) {
            if (pressed) setState(() => pressed = false);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed == null ? null : _invoke,
            onTapCancel: () {
              if (pressed) setState(() => pressed = false);
            },
            child: Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              foregroundDecoration: focused
                  ? BoxDecoration(border: Border.all(color: t.accent, width: 2))
                  : null,
              child: widget.tiltStrength == 0
                  ? widget.builder(context, pressed)
                  : BrockmannMotion(
                      value: pressed ? 1 : 0,
                      milliseconds: pressed ? 60 : 160,
                      builder: (c, progress) {
                        final strength = t.tilt && !t.motionReduced(c)
                            ? progress.clamp(0.0, 1.0) * widget.tiltStrength
                            : 0.0;
                        final matrix = Matrix4.identity()
                          ..setEntry(3, 2, -1 / 400)
                          ..rotateX(-_point.dy * 6 * math.pi / 180 * strength)
                          ..rotateY(_point.dx * 6 * math.pi / 180 * strength)
                          ..scaleByDouble(
                            1 - .03 * strength,
                            1 - .03 * strength,
                            1.0,
                            1,
                          );
                        return Transform(
                          alignment: Alignment.center,
                          transform: matrix,
                          child: widget.builder(c, pressed),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

enum BrockmannIcon {
  dotsThree,
  dotsThreeVertical,
  plus,
  minus,
  x,
  check,
  caretUp,
  caretDown,
  caretLeft,
  caretRight,
  arrowUp,
  arrowDown,
  arrowLeft,
  arrowRight,
  play,
  stop,
  record,
  search,
  settings,
  palette,
  calendar,
  clock,
  trash,
  copy,
  pencil,
  share,
  download,
  upload,
  info,
  warning,
  question,
  eye,
  eyeSlash,
  lock,
  unlock,
  heart,
  star,
  folder,
  document,
  image,
  user,
  bell,
  funnel,
  calendarCheck,
  arrowsClockwise;

  String get file => switch (this) {
    dotsThree => 'dots-three',
    dotsThreeVertical => 'dots-three-vertical',
    caretUp => 'caret-up',
    caretDown => 'caret-down',
    caretLeft => 'caret-left',
    caretRight => 'caret-right',
    arrowUp => 'arrow-up',
    arrowDown => 'arrow-down',
    arrowLeft => 'arrow-left',
    arrowRight => 'arrow-right',
    document => 'file',
    search => 'magnifying-glass',
    settings => 'sliders-horizontal',
    trash => 'trash',
    share => 'share-network',
    info => 'info',
    warning => 'warning',
    question => 'question',
    eyeSlash => 'eye-slash',
    unlock => 'lock-open',
    user => 'user',
    funnel => 'funnel',
    calendarCheck => 'calendar-check',
    arrowsClockwise => 'arrows-clockwise',
    _ => name,
  };
}

class BrockmannGlyph extends StatelessWidget {
  const BrockmannGlyph(this.icon, {super.key, this.size = 24, this.color});
  final BrockmannIcon icon;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/icons/${icon.file}${size <= 16 ? '-bold' : ''}.svg',
      package: 'brockmann',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? context.brockmann.secondary,
        BlendMode.srcIn,
      ),
    ),
  );
}

class BrockmannIconButton extends StatelessWidget {
  const BrockmannIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.expanded,
  });
  final BrockmannIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final bool? expanded;
  @override
  Widget build(BuildContext context) => BrockmannPressable(
    label: label,
    tooltip: label,
    onPressed: onPressed,
    builder: (c, pressed) => SizedBox(
      width: 48,
      height: 48,
      child: Center(
        child: BrockmannMotion(
          value: expanded == null ? (pressed ? 1 : 0) : (expanded! ? 1 : 0),
          milliseconds: expanded == null ? (pressed ? 60 : 160) : 240,
          builder: (c, value) {
            final p = c.brockmann.motionReduced(c)
                ? 0.0
                : value.clamp(0.0, 1.0);
            final direction = switch (icon) {
              BrockmannIcon.arrowUp ||
              BrockmannIcon.caretUp => const Offset(0, -4),
              BrockmannIcon.arrowDown ||
              BrockmannIcon.caretDown => const Offset(0, 4),
              BrockmannIcon.arrowLeft ||
              BrockmannIcon.caretLeft => const Offset(-4, 0),
              BrockmannIcon.arrowRight ||
              BrockmannIcon.caretRight => const Offset(4, 0),
              _ => Offset.zero,
            };
            final angle = expanded == null
                ? 0.0
                : switch (icon) {
                    BrockmannIcon.plus => 45.0,
                    BrockmannIcon.caretUp ||
                    BrockmannIcon.caretDown ||
                    BrockmannIcon.caretLeft ||
                    BrockmannIcon.caretRight => 180.0,
                    _ => 0.0,
                  };
            final color = onPressed == null
                ? c.brockmann.disabled
                : pressed
                ? c.brockmann.accent
                : c.brockmann.foreground;
            if (icon == BrockmannIcon.dotsThree ||
                icon == BrockmannIcon.dotsThreeVertical) {
              return SizedBox(
                width: 24,
                height: 24,
                child: CustomPaint(
                  painter: _DotsPainter(
                    icon == BrockmannIcon.dotsThreeVertical,
                    p,
                    color,
                  ),
                ),
              );
            }
            return Transform.translate(
              offset: expanded == null ? direction * p : Offset.zero,
              child: Transform.rotate(
                angle: angle * math.pi / 180 * p,
                child: BrockmannGlyph(icon, color: color),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.vertical, this.press, this.color);
  final bool vertical;
  final double press;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = -1; i <= 1; i++) {
      final along = 12 + i * (7 + 2 * press);
      canvas.drawCircle(
        vertical ? Offset(12, along) : Offset(along, 12),
        1.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.press != press || old.color != color || old.vertical != vertical;
}

class _ControlKeyIntent extends Intent {
  const _ControlKeyIntent(this.key);
  final LogicalKeyboardKey key;
}
