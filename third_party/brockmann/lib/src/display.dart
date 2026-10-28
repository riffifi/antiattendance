import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'foundation.dart';
import 'motion.dart';
import 'reorder.dart';

import 'package:flutter/scheduler.dart';

class BrockmannListItem extends StatelessWidget {
  const BrockmannListItem({
    super.key,
    required this.label,
    this.secondary,
    this.selected = false,
    this.onPressed,
    this.leading,
    this.trailing,
    this.chevron = false,
  });
  final String label;
  final String? secondary;
  final bool selected;
  final VoidCallback? onPressed;

  /// An optional glyph before the text, for rows where it aids recognition.
  final BrockmannIcon? leading;

  /// A widget after the text: a value, a badge or a switch-like control.
  final Widget? trailing;

  /// Shows a caret that signals navigation to another page.
  final bool chevron;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return BrockmannPressable(
      label: secondary == null ? label : '$label, $secondary',
      tiltStrength: .25,
      selected: selected,
      onPressed: onPressed,
      builder: (c, p) => BrockmannMotion(
        value: selected ? 1 : 0,
        milliseconds: 240,
        builder: (c, value) => Stack(
          children: [
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  heightFactor: value.clamp(0, 1),
                  child: SizedBox(width: 4, child: ColoredBox(color: t.accent)),
                ),
              ),
            ),
            AnimatedContainer(
              duration: t.duration(c, 180),
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              color: p ? t.surface : null,
              child: Row(
                children: [
                  if (leading != null) ...[
                    BrockmannGlyph(leading!),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BrockmannText(
                          label,
                          role: BrockmannType.value,
                          color: Color.lerp(
                            t.foreground,
                            t.accentText,
                            value.clamp(0, 1),
                          ),
                        ),
                        if (secondary != null) ...[
                          const SizedBox(height: 4),
                          BrockmannText(
                            secondary!,
                            role: BrockmannType.caption,
                            color: t.secondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 16),
                    trailing!,
                  ],
                  if (chevron) ...[
                    const SizedBox(width: 8),
                    BrockmannGlyph(BrockmannIcon.caretRight, size: 20),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum BrockmannTileSize { small, medium, large }

class BrockmannTile extends StatefulWidget {
  const BrockmannTile({
    super.key,
    required this.label,
    required this.value,
    this.active = false,
    this.onPressed,
    double? height,
    this.size = BrockmannTileSize.medium,
    this.width,
  }) : height =
           height ??
           (size == BrockmannTileSize.small
               ? 88
               : size == BrockmannTileSize.large
               ? 192
               : 128);
  final String label, value;
  final bool active;
  final VoidCallback? onPressed;
  final double height;
  final BrockmannTileSize size;
  final double? width;
  @override
  State<BrockmannTile> createState() => _BrockmannTileState();
}

class _BrockmannTileState extends State<BrockmannTile>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pulse.duration = context.brockmann.duration(context, 300);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final fg = widget.active ? t.onAccent : t.foreground;
    return SizedBox(
      width: widget.width,
      child: BrockmannPressable(
        label: '${widget.label}, ${widget.value}',
        tiltStrength: .5,
        onPressed: widget.onPressed == null
            ? null
            : () {
                _pulse.forward(from: 0);
                widget.onPressed!();
              },
        builder: (c, p) => AnimatedBuilder(
          animation: _pulse,
          builder: (c, _) {
            final pulse = _pulse.isAnimating ? 1 - _pulse.value : 0.0;
            return BrockmannReorderableItem(
              child: AnimatedContainer(
                duration: t.duration(c, p ? 60 : 160),
                constraints: BoxConstraints(minHeight: widget.height),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.active
                      ? Color.lerp(t.accent, Colors.black, p ? .18 : 0)
                      : Color.lerp(t.background, t.accent, pulse),
                  border: widget.active
                      ? null
                      : Border.all(color: t.line, width: 0),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BrockmannText(
                      widget.value,
                      role: widget.height >= 160
                          ? BrockmannType.pixelSquare
                          : BrockmannType.monoLarge,
                      color: Color.lerp(fg, t.onAccent, pulse),
                    ),
                    SizedBox(height: widget.height < 112 ? 8 : 24),
                    BrockmannText(
                      widget.label,
                      role: BrockmannType.label,
                      color: widget.active ? fg : t.secondary,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class BrockmannLiveTile extends StatefulWidget {
  const BrockmannLiveTile({
    super.key,
    required this.label,
    required this.primary,
    required this.secondary,
    this.interval = const Duration(seconds: 4),
    this.onPressed,
  });
  final String label, primary, secondary;
  final Duration interval;
  final VoidCallback? onPressed;
  @override
  State<BrockmannLiveTile> createState() => _BrockmannLiveTileState();
}

class _BrockmannLiveTileState extends State<BrockmannLiveTile>
    with SingleTickerProviderStateMixin {
  late final _flip = AnimationController(vsync: this);
  Timer? _timer;
  bool _secondary = false, _hover = false, _pressed = false;
  @override
  void initState() {
    super.initState();
    _flip.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _secondary = !_secondary);
        _flip.value = 0;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void didUpdateWidget(BrockmannLiveTile old) {
    super.didUpdateWidget(old);
    if (old.interval != widget.interval) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!TickerMode.valuesOf(context).enabled) {
      _flip.stop();
      return;
    }
    _timer = Timer.periodic(
      widget.interval < const Duration(milliseconds: 500)
          ? const Duration(milliseconds: 500)
          : widget.interval,
      (_) {
        if (_hover || _pressed || _flip.isAnimating) return;
        _flip.duration = context.brockmann.duration(context, 400);
        _flip.forward(from: 0);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _hover = true,
    onExit: (_) => _hover = false,
    child: Listener(
      onPointerDown: (_) => _pressed = true,
      onPointerUp: (_) => _pressed = false,
      onPointerCancel: (_) => _pressed = false,
      child: AnimatedBuilder(
        animation: _flip,
        builder: (c, _) {
          final t = _flip.value;
          final reduced = c.brockmann.motionReduced(c);
          final showSecondary = t < .5 ? _secondary : !_secondary;
          final angle = t < .5
              ? -90 * brockmannInExpo.transform(t * 2)
              : 90 * (1 - brockmannOutExpo.transform((t - .5) * 2));
          return Opacity(
            opacity: reduced ? ((t - .5).abs() * 2).clamp(0, 1) : 1,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, -1 / 800)
                ..rotateX(reduced ? 0 : angle * math.pi / 180),
              child: BrockmannTile(
                label: widget.label,
                value: showSecondary ? widget.secondary : widget.primary,
                active: true,
                onPressed: widget.onPressed,
              ),
            ),
          );
        },
      ),
    ),
  );
}

class BrockmannMeter extends StatefulWidget {
  const BrockmannMeter({
    super.key,
    required this.label,
    required this.db,
    this.axis = Axis.horizontal,
    this.extent = 160,
  });
  final String label;
  final double db, extent;
  final Axis axis;
  @override
  State<BrockmannMeter> createState() => _BrockmannMeterState();
}

class _BrockmannMeterState extends State<BrockmannMeter>
    with SingleTickerProviderStateMixin {
  late double peak = widget.db;
  Timer? _hold;
  late final Ticker _decay = createTicker((elapsed) {
    final seconds = (elapsed - _last).inMicroseconds / 1000000;
    _last = elapsed;
    setState(() => peak = math.max(widget.db, peak - 40 * seconds));
    if (peak <= widget.db) _decay.stop();
  });
  Duration _last = Duration.zero;
  @override
  void didUpdateWidget(BrockmannMeter old) {
    super.didUpdateWidget(old);
    if (widget.db >= peak) {
      peak = widget.db;
      _hold?.cancel();
      _decay.stop();
    }
    if (widget.db < peak && _hold?.isActive != true && !_decay.isActive) {
      _hold = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          _last = Duration.zero;
          _decay.start();
        }
      });
    }
  }

  @override
  void dispose() {
    _hold?.cancel();
    _decay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    value: '${widget.db.toStringAsFixed(1)} decibels',
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: widget.axis == Axis.vertical ? 4 : double.infinity,
        height: widget.axis == Axis.vertical ? widget.extent : 4,
        child: CustomPaint(
          painter: _MeterPainter(
            widget.db,
            peak,
            widget.axis,
            context.brockmann,
          ),
        ),
      ),
    ),
  );
}

class _MeterPainter extends CustomPainter {
  _MeterPainter(this.db, this.peak, this.axis, this.theme);
  final double db, peak;
  final Axis axis;
  final BrockmannThemeData theme;
  @override
  void paint(Canvas c, Size s) {
    final vertical = axis == Axis.vertical,
        level = ((db + 60) / 60).clamp(0.0, 1.0),
        held = ((peak + 60) / 60).clamp(0.0, 1.0);
    c.drawRect(Offset.zero & s, Paint()..color = theme.line);
    c.drawRect(
      vertical
          ? Rect.fromLTWH(0, s.height * (1 - level), s.width, s.height * level)
          : Rect.fromLTWH(0, 0, s.width * level, s.height),
      Paint()..color = theme.accent,
    );
    c.drawRect(
      vertical
          ? Rect.fromLTWH(
              0,
              (s.height * (1 - held)).clamp(0, s.height - 2),
              s.width,
              2,
            )
          : Rect.fromLTWH(
              (s.width * held).clamp(0, s.width - 2),
              0,
              2,
              s.height,
            ),
      Paint()..color = theme.foreground,
    );
    if (db > 0) {
      c.drawRect(
        vertical
            ? Rect.fromLTWH(0, 0, s.width, 8)
            : Rect.fromLTWH(s.width - 8, 0, 8, s.height),
        Paint()..color = theme.danger,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MeterPainter o) =>
      db != o.db || peak != o.peak || axis != o.axis || theme != o.theme;
}

class BrockmannProgress extends StatefulWidget {
  const BrockmannProgress({super.key, required this.label, this.value});
  final String label;
  final double? value;
  @override
  State<BrockmannProgress> createState() => _BrockmannProgressState();
}

class _BrockmannProgressState extends State<BrockmannProgress>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BrockmannProgress old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.value == null &&
        TickerMode.valuesOf(context).enabled &&
        !context.brockmann.motionReduced(context)) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Semantics(
      label: widget.label,
      value: widget.value == null
          ? 'In progress'
          : '${(widget.value!.clamp(0, 1) * 100).round()} percent',
      child: SizedBox(
        height: 16,
        child: LayoutBuilder(
          builder: (c, b) => widget.value != null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: widget.value!.clamp(0, 1),
                      end: widget.value!.clamp(0, 1),
                    ),
                    duration: t.duration(c, 240),
                    curve: brockmannEaseOut,
                    builder: (c, v, _) => Container(
                      height: 4,
                      width: b.maxWidth,
                      alignment: Alignment.centerLeft,
                      color: t.line,
                      child: SizedBox(
                        width: b.maxWidth * v,
                        child: ColoredBox(color: t.accent),
                      ),
                    ),
                  ),
                )
              : t.motionReduced(c)
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 4,
                    width: b.maxWidth * .3,
                    color: t.accent,
                  ),
                )
              : AnimatedBuilder(
                  animation: _controller,
                  builder: (c, _) => ClipRect(
                    child: Stack(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Positioned(
                            left: (() {
                              final phase = (_controller.value - i * .05) % 1;
                              return phase *
                                  phase *
                                  (3 - 2 * phase) *
                                  b.maxWidth;
                            })(),
                            top: 6,
                            width: 4,
                            height: 4,
                            child: ColoredBox(color: t.accent),
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
