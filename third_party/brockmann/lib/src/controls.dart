import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'foundation.dart';
import 'feedback.dart';
import 'motion.dart';
import 'interaction.dart';

enum BrockmannButtonStyle { primary, secondary, text }

/// A written action. Use one primary button per decision group. Set
/// [destructive] to present an irreversible action in the danger colour,
/// [icon] for a trailing glyph (e.g. an arrow for "continue"), and [expand]
/// to fill the available width on phones.
class BrockmannButton extends StatelessWidget {
  const BrockmannButton({
    super.key,
    required this.label,
    this.child,
    this.alignment = Alignment.centerLeft,
    this.onPressed,
    this.style = BrockmannButtonStyle.secondary,
    this.sound,
    this.icon,
    this.destructive = false,
    this.expand = false,
  });
  const BrockmannButton.primary({
    super.key,
    required this.label,
    this.child,
    this.alignment = Alignment.centerLeft,
    this.onPressed,
    this.sound,
    this.icon,
    this.destructive = false,
    this.expand = false,
  }) : style = BrockmannButtonStyle.primary;
  const BrockmannButton.text({
    super.key,
    required this.label,
    this.child,
    this.alignment = Alignment.centerLeft,
    this.onPressed,
    this.sound,
    this.icon,
    this.destructive = false,
  }) : style = BrockmannButtonStyle.text,
       expand = false;
  final String label;
  final Widget? child;
  final AlignmentGeometry alignment;
  final VoidCallback? onPressed;
  final BrockmannButtonStyle style;
  final BrockmannSound? sound;
  final BrockmannIcon? icon;
  final bool destructive, expand;
  @override
  Widget build(BuildContext context) => BrockmannPressable(
    label: label,
    excludeSemantics: child == null || label.isNotEmpty,
    tiltStrength: 1,
    onPressed: onPressed,
    sound:
        sound ??
        (style == BrockmannButtonStyle.primary
            ? BrockmannSound.activate
            : null),
    builder: (c, p) {
      final t = c.brockmann;
      final enabled = onPressed != null;
      final fill = destructive ? t.danger : t.accent;
      final onFill = destructive ? Colors.white : t.onAccent;
      final ink = !enabled
          ? t.disabled
          : style == BrockmannButtonStyle.primary
          ? onFill
          : destructive
          ? t.danger
          : t.foreground;
      final text = BrockmannText(
        label,
        role: style == BrockmannButtonStyle.text
            ? BrockmannType.body
            : BrockmannType.value,
        color: ink,
      );
      return AnimatedContainer(
        width: expand ? double.infinity : null,
        duration: t.duration(c, p ? 60 : 160),
        padding: EdgeInsets.symmetric(
          horizontal: style == BrockmannButtonStyle.text ? 0 : 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: style == BrockmannButtonStyle.primary
              ? (enabled ? Color.lerp(fill, onFill, p ? .12 : 0) : t.line)
              : p
              ? t.surface
              : null,
          border: style == BrockmannButtonStyle.secondary
              ? Border.all(
                  color: !enabled
                      ? t.line
                      : destructive
                      ? t.danger
                      : t.lineStrong,
                  width: 2,
                )
              : null,
        ),
        child: Align(
          alignment: alignment,
          widthFactor: expand ? null : 1,
          heightFactor: 1,
          child: child != null
              ? IconTheme(
                  data: IconThemeData(color: ink, size: 20),
                  child: DefaultTextStyle(
                    style:
                        (style == BrockmannButtonStyle.text
                                ? BrockmannType.body
                                : BrockmannType.value)
                            .style(color: ink),
                    child: child!,
                  ),
                )
              : icon == null
              ? text
              : Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Flexible(child: text),
                    if (expand) const Spacer() else const SizedBox(width: 12),
                    BrockmannGlyph(icon!, size: 20, color: ink),
                  ],
                ),
        ),
      );
    },
  );
}

class BrockmannSwitch extends StatefulWidget {
  const BrockmannSwitch({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.sound = true,
    this.compact = false,
  });
  final String label;
  final bool value, sound, compact;
  final ValueChanged<bool>? onChanged;
  @override
  State<BrockmannSwitch> createState() => _BrockmannSwitchState();
}

class _BrockmannSwitchState extends State<BrockmannSwitch> {
  double? _drag;
  double _dragStart = 0, _dragDelta = 0;
  void _commit(bool value) {
    if (value == widget.value || widget.onChanged == null) return;
    if (widget.sound) {
      BrockmannFeedbackScope.play(
        context,
        value ? BrockmannSound.toggleOn : BrockmannSound.toggleOff,
      );
    }
    widget.onChanged!(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return BrockmannPressable(
      label: widget.label,
      button: false,
      toggled: widget.value,
      onKey: widget.onChanged == null
          ? null
          : (key) {
              if (key == LogicalKeyboardKey.arrowLeft) _commit(false);
              if (key == LogicalKeyboardKey.arrowRight) _commit(true);
            },
      onPressed: widget.onChanged == null ? null : () => _commit(!widget.value),
      builder: (c, pressed) => BrockmannMotion(
        value: _drag ?? (widget.value ? 1 : 0),
        milliseconds: 180,
        immediate: _drag != null,
        builder: (c, raw) {
          final progress = raw.clamp(0.0, 1.0);
          return Padding(
            padding: EdgeInsets.symmetric(vertical: widget.compact ? 0 : 12),
            child: Row(
              mainAxisSize: widget.compact
                  ? MainAxisSize.min
                  : MainAxisSize.max,
              children: [
                if (!widget.compact) ...[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrockmannText(
                          widget.label,
                          color: widget.onChanged == null
                              ? t.disabled
                              : t.secondary,
                        ),
                        AnimatedSwitcher(
                          duration: t.duration(c, 170),
                          reverseDuration: t.duration(c, 90),
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, ?current],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: Offset(
                                      0,
                                      t.motionReduced(c) ? 0 : -.25,
                                    ),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: BrockmannText(
                            progress >= .5 ? 'On' : 'Off',
                            key: ValueKey(progress >= .5),
                            role: BrockmannType.value,
                            color: widget.onChanged == null
                                ? t.disabled
                                : t.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: widget.onChanged == null
                      ? null
                      : (_) {
                          _dragStart = progress;
                          _dragDelta = 0;
                          setState(() => _drag = progress);
                        },
                  onHorizontalDragUpdate: widget.onChanged == null
                      ? null
                      : (d) {
                          _dragDelta += d.delta.dx;
                          setState(
                            () => _drag = (_dragStart + _dragDelta / 28).clamp(
                              0,
                              1,
                            ),
                          );
                        },
                  onHorizontalDragEnd: widget.onChanged == null
                      ? null
                      : (d) {
                          final velocity = d.velocity.pixelsPerSecond.dx;
                          final next = velocity.abs() > 600
                              ? velocity > 0
                              : (_drag ?? progress) >= .5;
                          _commit(next);
                          setState(() => _drag = null);
                        },
                  onHorizontalDragCancel: () => setState(() => _drag = null),
                  child: SizedBox(
                    width: 60,
                    height: 48,
                    child: BrockmannMotion(
                      value: pressed ? 1 : 0,
                      milliseconds: pressed ? 60 : 220,
                      builder: (c, press) => CustomPaint(
                        painter: _SwitchPainter(
                          progress: progress,
                          press: press.clamp(0, 1),
                          theme: t,
                          enabled: widget.onChanged != null,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SwitchPainter extends CustomPainter {
  _SwitchPainter({
    required this.progress,
    required this.press,
    required this.theme,
    required this.enabled,
  });
  final double progress, press;
  final BrockmannThemeData theme;
  final bool enabled;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(4, (size.height - 20) / 2, 52, 20);
    canvas.drawRect(
      r,
      Paint()
        ..color = enabled
            ? Color.lerp(theme.lineStrong, theme.accent, progress)!
            : theme.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (enabled) {
      canvas.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width * progress, r.height),
        Paint()..color = theme.accent,
      );
      canvas.drawRect(
        r.deflate(2),
        Paint()..color = theme.accent.withValues(alpha: .25 * press),
      );
    }
    final width = 12 + 4 * press;
    final x = r.left + 6 + progress * 28 - (progress > .5 ? width - 12 : 0);
    canvas.drawRect(
      Rect.fromLTWH(x, r.top - 4, width, 28),
      Paint()..color = enabled ? theme.foreground : theme.disabled,
    );
  }

  @override
  bool shouldRepaint(_SwitchPainter old) =>
      old.progress != progress ||
      old.press != press ||
      old.theme != theme ||
      old.enabled != enabled;
}

class BrockmannSlider extends StatefulWidget {
  const BrockmannSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.step,
    this.defaultValue,
    this.formatValue,
    this.trackGradient,
  }) : assert(max > min),
       assert(value >= min && value <= max);
  final String label;
  final double value, min, max;
  final double? step, defaultValue;
  final ValueChanged<double>? onChanged;
  final String Function(double)? formatValue;
  final Gradient? trackGradient;
  @override
  State<BrockmannSlider> createState() => _BrockmannSliderState();
}

class _BrockmannSliderState extends State<BrockmannSlider> {
  bool _direct = false;
  double _grabOffset = 0;
  String get readout =>
      widget.formatValue?.call(widget.value) ??
      widget.value.toStringAsFixed(widget.max - widget.min <= 10 ? 2 : 0);
  double quantize(double v) {
    v = v.clamp(widget.min, widget.max);
    return widget.step == null
        ? v
        : (widget.min +
                  ((v - widget.min) / widget.step!).round() * widget.step!)
              .clamp(widget.min, widget.max);
  }

  void adjust(double delta) =>
      widget.onChanged?.call(quantize(widget.value + delta));
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final enabled = widget.onChanged != null;
    return BrockmannMotion(
      value: widget.value,
      immediate: _direct,
      milliseconds: 240,
      builder: (context, visual) => Semantics(
        label: widget.label,
        value: readout,
        slider: true,
        enabled: enabled,
        increasedValue:
            widget.formatValue?.call(
              quantize(
                widget.value + (widget.step ?? (widget.max - widget.min) / 100),
              ),
            ) ??
            '${quantize(widget.value + (widget.step ?? (widget.max - widget.min) / 100))}',
        decreasedValue:
            '${quantize(widget.value - (widget.step ?? (widget.max - widget.min) / 100))}',
        onIncrease: enabled
            ? () => adjust(widget.step ?? (widget.max - widget.min) / 100)
            : null,
        onDecrease: enabled
            ? () => adjust(-(widget.step ?? (widget.max - widget.min) / 100))
            : null,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent || !enabled) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              adjust(-(widget.step ?? (widget.max - widget.min) / 100));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              adjust(widget.step ?? (widget.max - widget.min) / 100);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: BrockmannText(
                        widget.label,
                        color: enabled ? t.secondary : t.disabled,
                      ),
                    ),
                    const SizedBox(width: 16),
                    BrockmannText(
                      widget.formatValue?.call(visual) ??
                          visual.toStringAsFixed(
                            widget.max - widget.min <= 10 ? 2 : 0,
                          ),
                      role: BrockmannType.monoValue,
                      color: enabled ? t.foreground : t.disabled,
                    ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (c, b) {
                  void set(Offset p) {
                    setState(() => _direct = true);
                    widget.onChanged?.call(
                      quantize(
                        widget.min +
                            ((p.dx - 12 - _grabOffset) /
                                        math.max(1, b.maxWidth - 24))
                                    .clamp(0, 1) *
                                (widget.max - widget.min),
                      ),
                    );
                  }

                  return BrockmannInteractionRegion(
                    enabled: enabled,
                    child: BrockmannHandleFeedback(
                      enabled: enabled,
                      isHandle: (p, size) =>
                          (p.dx -
                                  (12 +
                                      (widget.value - widget.min) /
                                          (widget.max - widget.min) *
                                          (size.width - 24)))
                              .abs() <=
                          24,
                      builder: (context, press) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onTapDown: enabled
                            ? (d) {
                                final thumb =
                                    12 +
                                    (widget.value - widget.min) /
                                        (widget.max - widget.min) *
                                        (b.maxWidth - 24);
                                _grabOffset =
                                    (d.localPosition.dx - thumb).abs() <= 24
                                    ? d.localPosition.dx - thumb
                                    : 0;
                                set(d.localPosition);
                              }
                            : null,
                        onTapUp: enabled
                            ? (d) {
                                set(d.localPosition);
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) setState(() => _direct = false);
                                });
                              }
                            : null,
                        onHorizontalDragStart: enabled
                            ? (d) {
                                final thumb =
                                    12 +
                                    (widget.value - widget.min) /
                                        (widget.max - widget.min) *
                                        (b.maxWidth - 24);
                                _grabOffset =
                                    (d.localPosition.dx - thumb).abs() <= 24
                                    ? d.localPosition.dx - thumb
                                    : 0;
                                set(d.localPosition);
                              }
                            : null,
                        onHorizontalDragUpdate: enabled
                            ? (d) => set(d.localPosition)
                            : null,
                        onHorizontalDragEnd: enabled
                            ? (_) => setState(() => _direct = false)
                            : null,
                        onHorizontalDragCancel: enabled
                            ? () => setState(() => _direct = false)
                            : null,
                        onDoubleTap: enabled && widget.defaultValue != null
                            ? () {
                                setState(() => _direct = false);
                                widget.onChanged!(widget.defaultValue!);
                              }
                            : null,
                        child: SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _SliderPainter(
                              press: press,
                              gradient: widget.trackGradient,
                              value:
                                  ((visual - widget.min) /
                                          (widget.max - widget.min))
                                      .clamp(0, 1),
                              zero: widget.min < 0 && widget.max > 0
                                  ? -widget.min / (widget.max - widget.min)
                                  : 0,
                              theme: t,
                              enabled: enabled,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    this.press = 0,
    required this.value,
    required this.zero,
    required this.theme,
    required this.enabled,
    this.gradient,
  });
  final Gradient? gradient;
  final double value, zero;
  final double press;
  final BrockmannThemeData theme;
  final bool enabled;
  @override
  void paint(Canvas c, Size s) {
    final y = s.height / 2;
    c.save();
    c.translate(12, 0);
    s = Size(math.max(1, s.width - 24), s.height);
    c.drawRect(
      Rect.fromLTWH(0, y - 1, s.width, 2),
      Paint()..color = theme.lineStrong,
    );
    if (gradient != null) {
      c.drawRect(
        Rect.fromLTWH(0, y - 4, s.width, 8),
        Paint()
          ..shader = gradient!.createShader(
            Rect.fromLTWH(0, y - 4, s.width, 8),
          ),
      );
    }
    final a = math.min(zero, value) * s.width,
        b = math.max(zero, value) * s.width;
    if (gradient == null) {
      c.drawRect(
        Rect.fromLTWH(a, y - 3, b - a, 6),
        Paint()..color = enabled ? theme.accent : theme.disabled,
      );
    }
    c.drawRect(
      Rect.fromCenter(
        center: Offset(value * s.width, y),
        width: 12 + 8 * press,
        height: 28 + 10 * press,
      ),
      Paint()
        ..color = enabled
            ? Color.lerp(theme.foreground, theme.accent, press)!
            : theme.disabled,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(covariant _SliderPainter o) =>
      o.press != press ||
      o.gradient != gradient ||
      o.value != value ||
      o.theme != theme ||
      o.enabled != enabled ||
      o.zero != zero;
}

class BrockmannKnob extends StatefulWidget {
  const BrockmannKnob({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.defaultValue,
    this.formatValue,
  }) : assert(max > min),
       assert(value >= min && value <= max);
  final String label;
  final double value, min, max;
  final double? defaultValue;
  final ValueChanged<double>? onChanged;
  final String Function(double)? formatValue;
  @override
  State<BrockmannKnob> createState() => _BrockmannKnobState();
}

class _BrockmannKnobState extends State<BrockmannKnob> {
  final _dialKey = GlobalKey();
  double _dragValue = 0, _angle = 0;
  bool _radial = false;
  Offset relative(Offset global) {
    final box = _dialKey.currentContext!.findRenderObject() as RenderBox;
    return box.globalToLocal(global) - box.size.center(Offset.zero);
  }

  double angle(Offset p) => math.atan2(p.dy, p.dx);
  void tap(Offset global) {
    final p = relative(global);
    if (p.distance < 20) return;
    final phase = (angle(p) - math.pi * .75 + math.pi * 2) % (math.pi * 2);
    final unit = phase > math.pi * 1.5
        ? (phase > math.pi * 1.75 ? 0.0 : 1.0)
        : phase / (math.pi * 1.5);
    widget.onChanged?.call(widget.min + unit * (widget.max - widget.min));
  }

  bool _dragging = false;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final enabled = widget.onChanged != null;
    final readout =
        widget.formatValue?.call(widget.value) ??
        widget.value.toStringAsFixed(widget.max - widget.min > 10 ? 0 : 2);
    return Semantics(
      label: widget.label,
      value: readout,
      slider: true,
      enabled: enabled,
      increasedValue:
          '${(widget.value + (widget.max - widget.min) / 100).clamp(widget.min, widget.max)}',
      decreasedValue:
          '${(widget.value - (widget.max - widget.min) / 100).clamp(widget.min, widget.max)}',
      onIncrease: enabled
          ? () => widget.onChanged!(
              (widget.value + (widget.max - widget.min) / 100).clamp(
                widget.min,
                widget.max,
              ),
            )
          : null,
      onDecrease: enabled
          ? () => widget.onChanged!(
              (widget.value - (widget.max - widget.min) / 100).clamp(
                widget.min,
                widget.max,
              ),
            )
          : null,
      child: Focus(
        onKeyEvent: (node, event) {
          if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          final step =
              (widget.max - widget.min) /
              100 *
              (HardwareKeyboard.instance.isShiftPressed ? .1 : 1);
          double? next;
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowDown) {
            next = widget.value - step;
          }
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowUp) {
            next = widget.value + step;
          }
          if (key == LogicalKeyboardKey.home) next = widget.min;
          if (key == LogicalKeyboardKey.end) next = widget.max;
          if (key == LogicalKeyboardKey.backspace) next = widget.defaultValue;
          if (next == null) return KeyEventResult.ignored;
          widget.onChanged!(next.clamp(widget.min, widget.max));
          return KeyEventResult.handled;
        },
        child: BrockmannInteractionRegion(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: enabled ? (d) => tap(d.globalPosition) : null,
            onPanStart: enabled
                ? (d) {
                    final p = relative(d.globalPosition);
                    _radial = p.distance >= 20;
                    _angle = angle(p);
                    _dragValue = widget.value;
                    setState(() => _dragging = true);
                  }
                : null,
            onPanEnd: enabled ? (_) => setState(() => _dragging = false) : null,
            onPanCancel: enabled
                ? () => setState(() => _dragging = false)
                : null,
            onPanUpdate: enabled
                ? (d) {
                    double delta;
                    if (_radial) {
                      final next = angle(relative(d.globalPosition));
                      delta =
                          (next - _angle + math.pi * 3) % (math.pi * 2) -
                          math.pi;
                      _angle = next;
                      delta /= math.pi * 1.5;
                    } else {
                      delta = -d.delta.dy / 140;
                    }
                    _dragValue =
                        (_dragValue +
                                delta *
                                    (widget.max - widget.min) *
                                    (HardwareKeyboard.instance.isShiftPressed
                                        ? .1
                                        : 1))
                            .clamp(widget.min, widget.max);
                    widget.onChanged!(_dragValue);
                  }
                : null,
            onDoubleTap: enabled && widget.defaultValue != null
                ? () => widget.onChanged!(widget.defaultValue!)
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96, minHeight: 112),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    key: _dialKey,
                    width: 96,
                    height: 96,
                    child: BrockmannMotion(
                      value: widget.value,
                      immediate: _dragging,
                      builder: (c, visual) => CustomPaint(
                        painter: _KnobPainter(
                          ((visual - widget.min) / (widget.max - widget.min))
                              .clamp(0, 1),
                          t,
                          enabled,
                        ),
                        child: Center(
                          child: ExcludeSemantics(
                            child: BrockmannText(
                              widget.formatValue?.call(visual) ??
                                  visual.toStringAsFixed(
                                    widget.max - widget.min > 10 ? 0 : 2,
                                  ),
                              role: BrockmannType.monoValue,
                              color: enabled ? t.foreground : t.disabled,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  BrockmannText(
                    widget.label,
                    role: BrockmannType.label,
                    color: enabled ? t.secondary : t.disabled,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter(this.value, this.theme, this.enabled);
  final double value;
  final BrockmannThemeData theme;
  final bool enabled;
  @override
  void paint(Canvas c, Size s) {
    final r = Rect.fromLTWH(10, 10, s.width - 20, s.height - 20);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    c.drawArc(r, math.pi * .75, math.pi * 1.5, false, p..color = theme.line);
    c.drawArc(
      r,
      math.pi * .75,
      math.pi * 1.5 * value,
      false,
      p..color = enabled ? theme.accent : theme.disabled,
    );
    final angle = math.pi * .75 + math.pi * 1.5 * value,
        center = s.center(Offset.zero);
    c.drawLine(
      center + Offset(math.cos(angle), math.sin(angle)) * 22,
      center + Offset(math.cos(angle), math.sin(angle)) * 31,
      Paint()
        ..color = enabled ? theme.foreground : theme.disabled
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _KnobPainter o) =>
      o.value != value || o.theme != theme || o.enabled != enabled;
}

class BrockmannTextField extends StatelessWidget {
  const BrockmannTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.error,
    this.enabled = true,
    this.multiline = false,
    this.keyboardType,
    this.obscureText = false,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.placeholder,
    this.leading,
    this.trailing,
    this.suffixText,
    this.hint,
    this.helper,
    this.focusNode,
    this.onSubmitted,
    this.textInputAction,
    this.maxLength,
    this.autofocus = false,
    this.autofillHints,
    this.mono,
    this.suffix,
  }) : assert(controller == null || initialValue == null);
  final String label;
  final TextEditingController? controller;
  final String? initialValue, error;

  /// Example text shown while the field is empty.
  final String? hint;

  /// Persistent guidance under the field; replaced by [error] when present.
  final String? helper;
  final ValueChanged<String>? onChanged, onSubmitted;
  final bool enabled, multiline, obscureText, autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final String? placeholder, suffixText;
  final Widget? leading, trailing;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final Iterable<String>? autofillHints;

  /// Use tabular mono figures. Defaults to true for multiline text.
  final bool? mono;

  /// A trailing widget inside the field, such as a unit or an icon button.
  final Widget? suffix;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label.isNotEmpty)
          BrockmannText(
            label,
            role: BrockmannType.label,
            color: enabled ? t.secondary : t.disabled,
          ),
        if (label.isNotEmpty) const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          textAlign: textAlign,
          initialValue: initialValue,
          onChanged: onChanged,
          enabled: enabled,
          obscureText: obscureText,
          focusNode: focusNode,
          onFieldSubmitted: onSubmitted,
          textInputAction: textInputAction,
          maxLength: maxLength,
          autofocus: autofocus,
          autofillHints: autofillHints,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 8 : 1,
          keyboardType:
              keyboardType ??
              (multiline ? TextInputType.multiline : TextInputType.text),
          style:
              ((mono ?? multiline)
                      ? BrockmannType.monoValue
                      : BrockmannType.body)
                  .style(color: t.foreground),
          cursorColor: t.accent,
          decoration: InputDecoration(
            prefixIcon: leading,
            suffixText: suffixText,
            isDense: true,
            contentPadding: const EdgeInsets.all(12),
            errorText: error,
            errorMaxLines: 3,
            hintText: hint ?? placeholder,
            hintStyle: BrockmannType.body.style(color: t.disabled),
            helperText: helper,
            helperMaxLines: 3,
            helperStyle: BrockmannType.caption.style(color: t.secondary),
            counterStyle: BrockmannType.caption.style(color: t.secondary),
            suffixIcon: suffix ?? trailing,
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: t.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: t.danger, width: 2),
            ),
            errorStyle: BrockmannType.caption.style(color: t.danger),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: t.lineStrong),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: t.lineStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: t.accent, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: t.line),
            ),
          ),
        ),
      ],
    );
  }
}
