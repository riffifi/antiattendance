import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'foundation.dart';
import 'interaction.dart';
import 'theme.dart';

/// The resting presentation; dragging down always reveals the narrow strip.
enum BrockmannCommandBarMode { minimized, compact, expanded }

@immutable
class BrockmannCommand {
  const BrockmannCommand({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onPressed,
  });
  final Widget icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
}

/// Phone application bar with a persistent ellipsis, direct vertical dragging,
/// and labels revealed on expansion. It owns its gestures, not page navigation.
class BrockmannCommandBar extends StatefulWidget {
  const BrockmannCommandBar({
    super.key,
    required this.commands,
    this.initialMode = BrockmannCommandBarMode.compact,
    this.active = true,
    this.onModeChanged,
    this.expandLabel = 'Expand app bar',
    this.collapseLabel = 'Collapse app bar',
    this.minimizeLabel = 'Minimize app bar',
  }) : assert(commands.length <= 4);

  /// Mini application bar: just enough for the corner ellipsis.
  static const minimizedExtent = 22.0;
  final List<BrockmannCommand> commands;
  final bool active;
  /// Reports presentation changes caused by user interaction.
  final ValueChanged<BrockmannCommandBarMode>? onModeChanged;
  final BrockmannCommandBarMode initialMode;
  final String expandLabel, collapseLabel, minimizeLabel;
  @override
  State<BrockmannCommandBar> createState() => _BrockmannCommandBarState();
}

class _BrockmannCommandBarState extends State<BrockmannCommandBar>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    value: _value(widget.initialMode),
  );
  late BrockmannCommandBarMode _mode = widget.initialMode;
  double _drag = 0;
  late BrockmannCommandBarMode _dragMode = _mode;
  bool _cancelled = false;
  static double _value(BrockmannCommandBarMode mode) => switch (mode) {
    BrockmannCommandBarMode.minimized => 0,
    BrockmannCommandBarMode.compact => .5,
    BrockmannCommandBarMode.expanded => 1,
  };

  @override
  void didUpdateWidget(BrockmannCommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _mode = BrockmannCommandBarMode.compact;
      _motion.value = .5;
    }
  }

  void _settle(BrockmannCommandBarMode mode) {
    if (!mounted || !widget.active) return;
    final changed = _mode != mode;
    setState(() => _mode = mode);
    if (changed) widget.onModeChanged?.call(mode);
    if (mounted) {
      _motion.animateTo(
        _value(mode),
        duration: context.brockmann.duration(context, 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final content = BrockmannInteractionRegion(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final width = math.min(
            112.0,
            math.max(
              1.0,
              (bounds.maxWidth - 96) / math.max(1, widget.commands.length),
            ),
          );
          var labelHeight = 0.0;
          for (final command in widget.commands) {
            final painter = TextPainter(
              text: TextSpan(
                text: command.label,
                style: BrockmannType.caption.style(),
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: math.max(1, width - 8));
            labelHeight = math.max(labelHeight, painter.height);
            painter.dispose();
          }
          final expandedHeight = math.max(88.0, 12 + 36 + 6 + labelHeight + 12);
          return AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final value = _motion.value;
              const mini = BrockmannCommandBar.minimizedExtent;
              final height = value <= .5
                  ? mini + (64 - mini) * value * 2
                  : 64 + (expandedHeight - 64) * (value - .5) * 2;
              final icons = (value * 2).clamp(0.0, 1.0);
              final labels = ((value - .5) * 2).clamp(0.0, 1.0);
              final hidden = value < .05;
              final expanded = _mode == BrockmannCommandBarMode.expanded;
              return PopScope(
                canPop: !widget.active || !expanded,
                onPopInvokedWithResult: (popped, _) {
                  if (!popped && expanded && widget.active) {
                    _settle(BrockmannCommandBarMode.compact);
                  }
                },
                child: Listener(
                  onPointerCancel: (_) {
                    _cancelled = true;
                    _settle(_dragMode);
                  },
                  child: GestureDetector(
                    dragStartBehavior: DragStartBehavior.down,
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) {
                      _motion.stop();
                      _dragMode = _mode;
                      _cancelled = false;
                      _drag = 0;
                    },
                    onVerticalDragUpdate: (event) {
                      _drag += event.delta.dy;
                      _motion.value =
                          (_motion.value -
                                  event.delta.dy /
                                      (expandedHeight -
                                          BrockmannCommandBar.minimizedExtent))
                              .clamp(0.0, 1.0);
                    },
                    onVerticalDragCancel: () => _settle(_mode),
                    onVerticalDragEnd: (event) {
                      if (_cancelled) return;
                      final velocity = event.velocity.pixelsPerSecond.dy;
                      _settle(
                        _drag.abs() < 12 && velocity.abs() < 250
                            ? _mode
                            : (velocity.abs() > 250 ? velocity : _drag) > 0
                            ? BrockmannCommandBarMode.minimized
                            : BrockmannCommandBarMode.expanded,
                      );
                    },
                    child: ColoredBox(
                      color: t.surface,
                      child: SafeArea(
                        top: false,
                        child: SizedBox(
                          height: height,
                          child: ClipRect(
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 0,
                                  left: 48,
                                  right: 48,
                                  child: ExcludeSemantics(
                                    excluding: hidden,
                                    child: IgnorePointer(
                                      ignoring: hidden,
                                      child: Opacity(
                                        opacity: icons,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (final command
                                                in widget.commands)
                                              SizedBox(
                                                width: width,
                                                child: Tooltip(
                                                  message:
                                                      command.tooltip ??
                                                      command.label,
                                                  excludeFromSemantics: true,
                                                  child: BrockmannPressable(
                                                    label:
                                                        command.tooltip ??
                                                        command.label,
                                                    onPressed:
                                                        command.onPressed ==
                                                            null
                                                        ? null
                                                        : () {
                                                            _settle(
                                                              BrockmannCommandBarMode
                                                                  .compact,
                                                            );
                                                            command
                                                                .onPressed!();
                                                          },
                                                    builder: (context, pressed) {
                                                      final ink =
                                                          command.onPressed ==
                                                              null
                                                          ? t.disabled
                                                          : t.foreground;
                                                      return Padding(
                                                        padding:
                                                            const EdgeInsets.fromLTRB(
                                                              4,
                                                              12,
                                                              4,
                                                              12,
                                                            ),
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Container(
                                                              width: 36,
                                                              height: 36,
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              decoration: BoxDecoration(
                                                                shape: BoxShape
                                                                    .circle,
                                                                border:
                                                                    Border.all(
                                                                      color:
                                                                          ink,
                                                                      width:
                                                                          1.5,
                                                                    ),
                                                                color: pressed
                                                                    ? ink
                                                                    : null,
                                                              ),
                                                              child: IconTheme(
                                                                data: IconThemeData(
                                                                  size: 20,
                                                                  color: pressed
                                                                      ? t.background
                                                                      : ink,
                                                                ),
                                                                child: command
                                                                    .icon,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 6,
                                                            ),
                                                            if (labels > 0)
                                                              Opacity(
                                                                opacity: labels,
                                                                child: Text(
                                                                  command.label,
                                                                  textAlign:
                                                                      TextAlign
                                                                          .center,
                                                                  style: BrockmannType
                                                                      .caption
                                                                      .style(
                                                                        color:
                                                                            ink,
                                                                      ),
                                                                ),
                                                              ),
                                                          ],
                                                        ),
                                                      );
                                                    },
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
                                  top: 0,
                                  right: 0,
                                  child: Semantics(
                                    customSemanticsActions: {
                                      CustomSemanticsAction(
                                        label: widget.minimizeLabel,
                                      ): () => _settle(
                                        BrockmannCommandBarMode.minimized,
                                      ),
                                    },
                                    child: BrockmannPressable(
                                      label: expanded
                                          ? widget.collapseLabel
                                          : widget.expandLabel,
                                      onPressed: () => _settle(
                                        expanded
                                            ? BrockmannCommandBarMode.compact
                                            : BrockmannCommandBarMode.expanded,
                                      ),
                                      builder: (context, pressed) => SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Align(
                                          alignment: const Alignment(0, -.8),
                                          child: Row(
                                            key: const ValueKey(
                                              'brockmann-appbar-ellipsis',
                                            ),
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              for (var i = 0; i < 3; i++)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 2,
                                                      ),
                                                  child: Container(
                                                    width: 3,
                                                    height: 3,
                                                    decoration: BoxDecoration(
                                                      color: pressed
                                                          ? t.accentText
                                                          : t.foreground,
                                                      shape: BoxShape.circle,
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
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: t.surface,
        systemNavigationBarDividerColor: t.surface,
        systemNavigationBarIconBrightness: t.light
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: content,
    );
  }
}
