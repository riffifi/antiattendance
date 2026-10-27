import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'foundation.dart';
import 'feedback.dart';
import 'motion.dart';

/// Fitting options never disappear. Overflow pans only enough to reveal selection.
class BrockmannPivot extends StatefulWidget {
  const BrockmannPivot({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  }) : assert(selected >= 0),
       assert(options.length == 0 || selected < options.length);
  final List<String> options;
  final int selected;
  final ValueChanged<int>? onChanged;
  final bool compact;
  @override
  State<BrockmannPivot> createState() => _BrockmannPivotState();
}

class _BrockmannPivotState extends State<BrockmannPivot> {
  double _swipe = 0;
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  List<GlobalKey> _keys = [];
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant BrockmannPivot old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected || old.options != widget.options) {
      _schedule();
    }
  }

  void _schedule() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted ||
        widget.options.isEmpty ||
        !_scroll.hasClients ||
        widget.selected >= _keys.length) {
      return;
    }
    final box =
        _keys[widget.selected].currentContext?.findRenderObject() as RenderBox?;
    final viewport = _viewport.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || viewport == null) return;
    final x = box.localToGlobal(Offset.zero, ancestor: viewport).dx;
    final current = _scroll.offset;
    final delta = x < 12
        ? x - 12
        : x + box.size.width > viewport.size.width - 12
        ? x + box.size.width - (viewport.size.width - 12)
        : 0.0;
    final target = (current + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((target - current).abs() < .5) return;
    final t = context.brockmann;
    if (t.motionReduced(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: t.duration(context, 180),
        curve: brockmannEaseOut,
      );
    }
  });
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    if (_keys.length != widget.options.length) {
      _keys = List.generate(widget.options.length, (_) => GlobalKey());
    }
    final role = widget.compact ? BrockmannType.body : BrockmannType.title;
    final sizes = widget.options.map((label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: role.style()),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      return Size(
        math.max(48, painter.width),
        math.max(48, painter.height + 20),
      );
    }).toList();
    final height = sizes.fold(48.0, (h, s) => math.max(h, s.height));
    final offset =
        12.0 +
        sizes.take(widget.selected).fold(0.0, (x, s) => x + s.width + 24);
    return SizedBox(
      key: _viewport,
      height: height,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: widget.compact || widget.onChanged == null
            ? null
            : (_) => _swipe = 0,
        onHorizontalDragUpdate: widget.compact || widget.onChanged == null
            ? null
            : (d) => _swipe += d.delta.dx,
        onHorizontalDragEnd: widget.compact || widget.onChanged == null
            ? null
            : (d) {
                final velocity = d.velocity.pixelsPerSecond.dx;
                if (_swipe.abs() < 36 && velocity.abs() < 400) return;
                final direction = velocity.abs() > 400 ? velocity : _swipe;
                final next = (widget.selected + (direction < 0 ? 1 : -1)).clamp(
                  0,
                  widget.options.length - 1,
                );
                if (next != widget.selected) {
                  BrockmannFeedbackScope.play(context, BrockmannSound.select);
                  widget.onChanged!(next);
                }
              },
        child: SingleChildScrollView(
          controller: _scroll,
          physics: widget.compact ? null : const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          scrollDirection: Axis.horizontal,
          child: Stack(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.options.length; i++)
                    Padding(
                      key: _keys[i],
                      padding: EdgeInsets.only(
                        right: i == widget.options.length - 1 ? 0 : 24,
                      ),
                      child: SizedBox(
                        width: sizes[i].width,
                        height: height,
                        child: BrockmannPressable(
                          label: widget.options[i],
                          selected: widget.selected == i,
                          onKey: widget.onChanged == null
                              ? null
                              : (key) {
                                  final next = key == LogicalKeyboardKey.home
                                      ? 0
                                      : key == LogicalKeyboardKey.end
                                      ? widget.options.length - 1
                                      : (widget.selected +
                                                (key ==
                                                            LogicalKeyboardKey
                                                                .arrowLeft ||
                                                        key ==
                                                            LogicalKeyboardKey
                                                                .arrowUp
                                                    ? -1
                                                    : 1))
                                            .clamp(
                                              0,
                                              widget.options.length - 1,
                                            );
                                  if (next != widget.selected) {
                                    BrockmannFeedbackScope.play(
                                      context,
                                      BrockmannSound.select,
                                    );
                                    widget.onChanged!(next);
                                  }
                                },
                          onPressed: widget.onChanged == null
                              ? null
                              : () {
                                  if (i != widget.selected) {
                                    BrockmannFeedbackScope.play(
                                      context,
                                      BrockmannSound.select,
                                    );
                                    widget.onChanged!(i);
                                  }
                                },
                          builder: (c, p) => Align(
                            alignment: Alignment.centerLeft,
                            child: BrockmannText(
                              widget.options[i],
                              role: role,
                              color: widget.onChanged == null
                                  ? t.disabled
                                  : i == widget.selected
                                  ? t.foreground
                                  : widget.compact
                                  ? t.secondary
                                  : t.disabled,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (widget.compact && widget.options.isNotEmpty)
                AnimatedPositioned(
                  duration: t.duration(context, 180),
                  curve: brockmannEaseOut,
                  left: offset,
                  bottom: 0,
                  width: sizes[widget.selected].width,
                  height: 2,
                  child: ColoredBox(
                    color: widget.onChanged == null ? t.disabled : t.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A controlled choice with a full-page phone list or an anchored wide-screen menu.
enum BrockmannPickerPresentation { adaptive, fullPage, anchored }

class BrockmannPicker extends StatefulWidget {
  const BrockmannPicker({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.presentation = BrockmannPickerPresentation.adaptive,
  }) : assert(selected >= 0);
  final BrockmannPickerPresentation presentation;
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int>? onChanged;
  @override
  State<BrockmannPicker> createState() => _BrockmannPickerState();
}

class _BrockmannPickerState extends State<BrockmannPicker>
    with SingleTickerProviderStateMixin {
  final _fieldKey = GlobalKey(), _valueKey = GlobalKey();
  bool _handoff = false, _open = false, _hover = false;
  int get selected => widget.options.isEmpty
      ? 0
      : widget.selected.clamp(0, widget.options.length - 1);
  OverlayEntry? _quick;
  LocalHistoryEntry? _history;
  Timer? _edgeTimer;
  _PickerSurface? _quickSurface;
  late final _quickMotion = AnimationController(vsync: this);
  bool _quickClosing = false;
  Offset _finger = Offset.zero;
  bool get _anchored =>
      widget.presentation == BrockmannPickerPresentation.anchored ||
      (widget.presentation == BrockmannPickerPresentation.adaptive &&
          MediaQuery.sizeOf(context).width >= 720 &&
          MediaQuery.textScalerOf(context).scale(16) <= 24);

  void _quickStart(LongPressStartDetails d) {
    if (_open ||
        !_anchored ||
        widget.onChanged == null ||
        widget.options.isEmpty) {
      return;
    }
    final box = _fieldKey.currentContext!.findRenderObject() as RenderBox;
    final value = _valueBounds()!;
    final t = context.brockmann;
    _quickClosing = false;
    _quickMotion.duration = t.duration(context, 220);
    _quickMotion.reverseDuration = t.duration(context, 200);
    _quickSurface = _PickerSurface(
      label: widget.label,
      options: List.of(widget.options),
      selected: selected,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      closedValue: value,
      liveValue: _valueBounds,
      fullPage: false,
      theme: t.copyWith(reduceMotion: t.motionReduced(context)),
      animation: _quickMotion,
      onCancel: () => _quickEnd(false),
      onSelected: (_) {},
    );
    _open = true;
    _history = LocalHistoryEntry(
      onRemove: () {
        _history = null;
        _quickEnd(false);
      },
    );
    ModalRoute.of(context)?.addLocalHistoryEntry(_history!);
    _quick = OverlayEntry(
      builder: (c) => AnimatedBuilder(
        animation: _quickMotion,
        builder: (c, _) => Stack(
          children: [
            ModalBarrier(
              color: Colors.black.withValues(
                alpha:
                    (t.light ? .4 : .6) *
                    Curves.ease.transform(_quickMotion.value),
              ),
              dismissible: false,
            ),
            IgnorePointer(child: _quickSurface!.build(c)),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_quick!);
    setState(() {});
    _quickMotion.forward(from: 0);
    BrockmannFeedbackScope.of(context)?.play(BrockmannSound.open);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _quickMove(d.globalPosition),
    );
    _edgeTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final surface = _quickSurface;
      final scroll = surface?._scroll;
      final panel = surface?._geometry?.panel;
      if (_quickClosing ||
          panel == null ||
          scroll == null ||
          !scroll.hasClients) {
        return;
      }
      final direction = _finger.dy < panel.top + 36
          ? -1
          : _finger.dy > panel.bottom - 36
          ? 1
          : 0;
      if (direction != 0 &&
          _finger.dx >= panel.left &&
          _finger.dx <= panel.right) {
        scroll.jumpTo(
          (scroll.offset + direction * 5).clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
        );
        _updateCandidate();
      }
    });
  }

  void _quickMove(Offset global) {
    if (_quick == null || _quickClosing) return;
    _finger = global;
    _updateCandidate();
  }

  void _updateCandidate() {
    final surface = _quickSurface;
    final geometry = surface?._geometry;
    if (surface == null || geometry == null || _quickClosing) return;
    final next = geometry.panel.contains(_finger)
        ? ((_finger.dy - geometry.panel.top - 8 + surface._offset) /
                  geometry.rowHeight)
              .floor()
              .clamp(0, surface.options.length - 1)
        : null;
    if (surface.previewCandidate != next) {
      surface.previewCandidate = next;
      _quick?.markNeedsBuild();
    }
  }

  Future<void> _quickEnd(bool commit) async {
    if (_quick == null || _quickClosing) return;
    _quickClosing = true;
    _edgeTimer?.cancel();
    final result = commit ? _quickSurface!.previewCandidate : null;
    _quickSurface!.close(result);
    final history = _history;
    _history = null;
    history?.remove();
    if (result != null && result != selected && mounted) {
      BrockmannFeedbackScope.of(context)?.selection();
      widget.onChanged?.call(result);
    }
    // Use the same full closing duration and label handoff as a tapped choice.
    try {
      await _quickMotion
          .animateBack(0, duration: _quickMotion.reverseDuration)
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    _removeQuick();
    setState(() {});
  }

  void _removeQuick() {
    _edgeTimer?.cancel();
    _quick?.remove();
    _quick?.dispose();
    _quick = null;
    _quickSurface?.dispose();
    _quickSurface = null;
    final history = _history;
    _history = null;
    history?.remove();
    _open = false;
  }

  @override
  void dispose() {
    _quickClosing = true;
    _quickMotion.dispose();
    _removeQuick();
    super.dispose();
  }

  Rect? _valueBounds() {
    final field = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final value = _valueKey.currentContext?.findRenderObject() as RenderBox?;
    if (field == null || value == null || !field.hasSize || !value.hasSize) {
      return null;
    }
    final topLeft = value.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      field.size.width - 32,
      value.size.height,
    );
  }

  Future<void> _show() async {
    if (_open || widget.onChanged == null || widget.options.isEmpty) return;
    final field = _fieldKey.currentContext!.findRenderObject()! as RenderBox;
    final value = _valueKey.currentContext!.findRenderObject()! as RenderBox;
    final t = context.brockmann;
    final media = MediaQuery.of(context);
    final wide =
        widget.presentation == BrockmannPickerPresentation.anchored ||
        (widget.presentation == BrockmannPickerPresentation.adaptive &&
            media.size.width >= 720 &&
            media.textScaler.scale(16) <= 24);
    final feedback = BrockmannFeedbackScope.of(context);
    final original = selected;
    final route = _PickerRoute(
      label: widget.label,
      options: List.of(widget.options),
      selected: original,
      anchor: field.localToGlobal(Offset.zero) & field.size,
      closedValue: Rect.fromLTWH(
        value.localToGlobal(Offset.zero).dx,
        value.localToGlobal(Offset.zero).dy,
        field.size.width - 32,
        value.size.height,
      ),
      liveValue: _valueBounds,
      fullPage: !wide,
      theme: t.copyWith(reduceMotion: t.motionReduced(context)),
      onSelected: (index) {
        if (index != original && mounted) {
          widget.onChanged?.call(index);
        }
        feedback?.play(
          index == original ? BrockmannSound.close : BrockmannSound.select,
        );
      },
    );
    setState(() {
      _open = true;
      _handoff = wide;
    });
    feedback?.play(BrockmannSound.open);
    final result = await Navigator.of(context).push<int>(route);
    if (result == null) feedback?.play(BrockmannSound.close);
    // Keep the underlying copy hidden until the carried label has landed.
    await route.completed;
    if (mounted) {
      setState(() {
        _open = false;
        _handoff = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final enabled = widget.onChanged != null && widget.options.isNotEmpty;
    return Visibility(
      visible: !_handoff,
      maintainSize: true,
      maintainState: true,
      maintainAnimation: true,
      child: GestureDetector(
        onLongPressStart: enabled && _anchored ? _quickStart : null,
        onLongPressMoveUpdate: enabled && _anchored
            ? (d) => _quickMove(d.globalPosition)
            : null,
        onLongPressEnd: (_) => _quickEnd(true),
        onLongPressCancel: () => _quickEnd(false),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: BrockmannPressable(
            key: _fieldKey,
            label:
                '${widget.label}, ${widget.options.isEmpty ? 'No options' : widget.options[selected]}',
            onPressed: enabled ? _show : null,
            builder: (c, p) => Opacity(
              opacity: _quick == null ? 1 : 0,
              child: Container(
                constraints: const BoxConstraints(minHeight: 80),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                foregroundDecoration: BoxDecoration(
                  border: Border.all(
                    color: !enabled
                        ? Colors.transparent
                        : p
                        ? t.foreground
                        : _hover
                        ? t.lineStrong
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BrockmannText(
                      widget.label,
                      role: BrockmannType.label,
                      color: enabled ? t.secondary : t.disabled,
                    ),
                    const SizedBox(height: 4),
                    BrockmannText(
                      widget.options.isEmpty
                          ? 'No options'
                          : widget.options[selected],
                      key: _valueKey,
                      role: BrockmannType.value,
                      color: enabled ? t.foreground : t.disabled,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerGeometry {
  const _PickerGeometry(this.panel, this.rowHeight, this.textHeights);
  final Rect panel;
  final double rowHeight;
  final List<double> textHeights;
  Rect textRect(int index, double scroll) => Rect.fromLTWH(
    panel.left + 16,
    panel.top +
        8 +
        index * rowHeight -
        scroll +
        (rowHeight - textHeights[index]) / 2,
    panel.width - 32,
    textHeights[index],
  );
  Rect selectedPanel(int index, double scroll) => Rect.fromLTWH(
    panel.left,
    panel.top + index * rowHeight - scroll,
    panel.width,
    rowHeight + 16,
  ).intersect(panel);
}

class _PickerExit {
  const _PickerExit(
    this.reveal,
    this.text,
    this.index,
    this.start,
    this.opacity,
  );
  final Rect reveal, text;
  final int index;
  final double start, opacity;
}

class _PickerRoute extends PageRoute<int> {
  _PickerRoute({
    required this.label,
    required this.options,
    required this.selected,
    required this.anchor,
    required this.closedValue,
    required this.liveValue,
    required this.fullPage,
    required this.theme,
    required this.onSelected,
  });
  @override
  bool get opaque => fullPage;
  @override
  bool get maintainState => true;
  final String label;
  final List<String> options;
  final int selected;
  final Rect anchor, closedValue;
  final Rect? Function() liveValue;
  final bool fullPage;
  final BrockmannThemeData theme;
  final ValueChanged<int> onSelected;
  bool _closing = false;
  late final _surface = _PickerSurface(
    label: label,
    options: options,
    selected: selected,
    anchor: anchor,
    closedValue: closedValue,
    liveValue: liveValue,
    fullPage: fullPage,
    theme: theme,
    animation: animation!,
    onCancel: () => navigator?.pop(),
    onSelected: (index) {
      onSelected(index);
      navigator?.pop(index);
    },
  );
  @override
  Color get barrierColor =>
      Colors.black.withValues(alpha: theme.light ? .4 : .6);
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => 'Close $label';
  @override
  Duration get transitionDuration => Duration(
    milliseconds:
        (theme.reduceMotion ? 100 : (fullPage ? 480 : 220) * theme.motionScale)
            .round(),
  );
  @override
  Duration get reverseTransitionDuration => Duration(
    milliseconds:
        (theme.reduceMotion ? 100 : (fullPage ? 260 : 200) * theme.motionScale)
            .round(),
  );
  @override
  bool didPop(int? result) {
    _closing = true;
    _surface.close(result);
    final popped = super.didPop(result);
    if (popped) {
      controller?.animateBack(0, duration: reverseTransitionDuration);
    }
    return popped;
  }

  @override
  void dispose() {
    _surface.dispose();
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _surface.build(context);
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!fullPage) {
      return AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (c, child) => IgnorePointer(
          ignoring: _closing,
          child: ExcludeFocus(excluding: _closing, child: child!),
        ),
      );
    }
    return _FullPickerTransition(route: this, child: child);
  }
}

/// The picker keeps Metro feather motion while forwarding Android's predictive
/// Back events to the route's own gesture controller.
class _FullPickerTransition extends StatefulWidget {
  const _FullPickerTransition({required this.route, required this.child});
  final _PickerRoute route;
  final Widget child;
  @override
  State<_FullPickerTransition> createState() => _FullPickerTransitionState();
}

class _FullPickerTransitionState extends State<_FullPickerTransition>
    with WidgetsBindingObserver {
  bool _gesture = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.route.animation!.addStatusListener(_status);
  }

  void _status(AnimationStatus status) {
    if (status == AnimationStatus.completed && _gesture) {
      widget.route._surface.gesturePreview = false;
      setState(() => _gesture = false);
    }
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    final route = widget.route;
    if (event.isButtonEvent || !route.isCurrent || !route.popGestureEnabled) {
      return false;
    }
    setState(() => _gesture = true);
    route._surface.gesturePreview = true;
    route.handleStartBackGesture(progress: 1 - event.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) => widget
      .route
      .handleUpdateBackGestureProgress(progress: 1 - event.progress);
  @override
  void handleCancelBackGesture() => widget.route.handleCancelBackGesture();
  @override
  void handleCommitBackGesture() => widget.route.handleCommitBackGesture();
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.route.animation!.removeStatusListener(_status);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.route.animation!,
    child: widget.child,
    builder: (c, child) {
      final route = widget.route;
      final surface = route._surface;
      final value = route.animation!.value;
      final exit = surface._fullExitStart;
      final opacity = _gesture
          ? value
          : exit == null
          ? route.theme.reduceMotion
                ? value
                : Curves.easeOutCubic.transform((value * .48 / .20).clamp(0, 1))
          : surface._fullExitOpacity *
                Curves.easeInOutCubic.transform(
                  (value / math.max(.000001, exit)).clamp(0, 1),
                );
      return IgnorePointer(
        ignoring: route._closing || _gesture,
        child: ExcludeFocus(
          excluding: route._closing,
          child: Opacity(
            key: const ValueKey('brockmann-full-picker-fade'),
            opacity: opacity,
            child: child,
          ),
        ),
      );
    },
  );
}

class _PickerSurface {
  _PickerSurface({
    required this.label,
    required this.options,
    required this.selected,
    required this.anchor,
    required this.closedValue,
    required this.liveValue,
    required this.fullPage,
    required this.theme,
    required this.onSelected,
    required this.onCancel,
    required this.animation,
  });
  final String label;
  final List<String> options;
  final int selected;
  final Rect anchor, closedValue;
  final Rect? Function() liveValue;
  final bool fullPage;
  final BrockmannThemeData theme;
  final ValueChanged<int> onSelected;
  final VoidCallback onCancel;
  final Animation<double> animation;
  int? previewCandidate;
  bool gesturePreview = false;
  double? _fullExitStart;
  double _fullExitOpacity = 1;
  ScrollController? _scroll;
  double _initialOffset = 0;
  bool _closing = false;
  _PickerGeometry? _geometry;
  _PickerExit? _exit;
  double get _offset =>
      _scroll?.hasClients == true ? _scroll!.offset : _initialOffset;
  double get _opening => theme.reduceMotion
      ? 1
      : brockmannOutExpo.transform(
          ((animation.value) * (fullPage ? 2 : 1)).clamp(0, 1),
        );
  Rect _reveal(_PickerGeometry geometry) => Rect.lerp(
    geometry.selectedPanel(selected, _offset),
    geometry.panel,
    _opening,
  )!;
  double get _opacity {
    final exit = _exit;
    if (theme.reduceMotion) {
      return exit == null
          ? animation.value
          : (animation.value / math.max(.000001, exit.start)).clamp(0, 1);
    }
    return exit == null
        ? brockmannOutExpo.transform((animation.value * 220 / 120).clamp(0, 1))
        : exit.opacity *
              (1 -
                  brockmannInExpo.transform(
                    ((exit.start - animation.value) /
                            math.max(.000001, exit.start))
                        .clamp(0, 1),
                  ));
  }

  void close(int? result) {
    _closing = true;
    if (fullPage) {
      _fullExitStart = animation.value;
      _fullExitOpacity = theme.reduceMotion
          ? animation.value
          : Curves.easeOutCubic.transform(
              (animation.value * .48 / .20).clamp(0, 1),
            );
    }
    final g = _geometry;
    if (g != null && !fullPage) {
      final chosen = result ?? selected;
      final opacity = brockmannOutExpo.transform(
        ((animation.value) * 220 / 120).clamp(0, 1),
      );
      _exit = _PickerExit(
        _reveal(g),
        g.textRect(chosen, _offset),
        chosen,
        animation.value,
        opacity,
      );
    }
  }

  void dispose() => _scroll?.dispose();
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = fullPage
        ? media.size.width - 48
        : math.min(anchor.width, media.size.width - 48);
    final role = fullPage ? BrockmannType.heading : BrockmannType.value;
    final textHeights = options
        .map((option) {
          final measure = TextPainter(
            text: TextSpan(text: option, style: role.style()),
            textDirection: Directionality.of(context),
            textScaler: media.textScaler,
          )..layout(maxWidth: math.max(1, width - 32));
          final height = measure.height;
          measure.dispose();
          return height;
        })
        .toList(growable: false);
    final rowHeight = math.max(
      fullPage ? 56.0 : 48.0,
      textHeights.reduce(math.max) + 24,
    );
    final top = media.padding.top + 16;
    final bottom = media.size.height - media.padding.bottom - 16;
    final height = math.min(
      rowHeight * options.length + 16,
      math.max(0.0, bottom - top),
    );
    final x = anchor.left.clamp(
      24.0,
      math.max(24.0, media.size.width - width - 24),
    );
    final desiredY =
        closedValue.top -
        (rowHeight - textHeights[selected]) / 2 -
        8 -
        selected * rowHeight;
    final y = desiredY.clamp(top, math.max(top, bottom - height));
    final geometry = _PickerGeometry(
      Rect.fromLTWH(x.toDouble(), y.toDouble(), width, height),
      rowHeight,
      textHeights,
    );
    _geometry = geometry;
    final initialScroll = fullPage
        ? selected * rowHeight
        : (geometry.textRect(selected, 0).top - closedValue.top).clamp(
            0.0,
            math.max(0.0, options.length * rowHeight + 16 - height),
          );
    if (_scroll == null) {
      _initialOffset = initialScroll.toDouble();
      _scroll = ScrollController(initialScrollOffset: _initialOffset);
    }
    final list = _PickerList(
      label: label,
      options: options,
      selected: selected,
      rowHeight: rowHeight,
      fullPage: fullPage,
      animation: animation,
      scroll: _scroll!,
      closingIndex: () => _exit?.index,
      panelOpacity: () => _opacity,
      previewCandidate: previewCandidate,
      exitStart: () => _fullExitStart,
      gesturePreview: () => gesturePreview,
      onSelected: (index) {
        if (_closing) return;
        onSelected(index);
      },
    );
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: label,
      child: fullPage
          ? ColoredBox(
              color: theme.background,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          BrockmannIconButton(
                            icon: BrockmannIcon.arrowLeft,
                            label: 'Close $label',
                            onPressed: onCancel,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: BrockmannText(
                              label,
                              role: BrockmannType.heading,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: list),
                  ],
                ),
              ),
            )
          : AnimatedBuilder(
              animation: animation,
              child: list,
              builder: (c, list) {
                final exit = _exit;
                final closing = exit == null
                    ? 0.0
                    : brockmannOutExpo.transform(
                        ((exit.start - animation.value) /
                                math.max(.000001, exit.start))
                            .clamp(0, 1),
                      );
                final destination = liveValue() ?? closedValue;
                final target = Rect.fromLTWH(
                  destination.left - 16,
                  destination.top - (rowHeight - destination.height) / 2 - 8,
                  destination.width + 32,
                  rowHeight + 16,
                );
                final panel = exit == null
                    ? _reveal(geometry)
                    : theme.reduceMotion
                    ? geometry.panel
                    : Rect.lerp(exit.reveal, target, closing)!;
                final opacity = _opacity;
                final carried = exit == null
                    ? null
                    : theme.reduceMotion
                    ? exit.text
                    : Rect.lerp(
                        exit.text,
                        Rect.fromLTWH(
                          destination.left,
                          destination.top,
                          destination.width,
                          geometry.textHeights[exit.index],
                        ),
                        closing,
                      );
                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: panel,
                      child: Opacity(
                        opacity: opacity,
                        child: DecoratedBox(
                          key: const ValueKey('brockmann-picker-panel'),
                          decoration: BoxDecoration(
                            color: theme.surface,
                            border: Border.all(color: theme.line, width: 0),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: geometry.panel,
                      child: ClipRect(
                        clipper: _PickerClip(
                          panel.shift(-geometry.panel.topLeft),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: list,
                        ),
                      ),
                    ),
                    if (carried != null)
                      Positioned.fromRect(
                        rect: carried,
                        child: ExcludeSemantics(
                          child: Opacity(
                            opacity: theme.reduceMotion ? opacity : 1,
                            child: BrockmannText(
                              options[exit!.index],
                              key: const ValueKey('brockmann-picker-carry'),
                              role: BrockmannType.value,
                              color: Color.lerp(
                                theme.accentText,
                                theme.foreground,
                                closing,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class _PickerList extends StatefulWidget {
  const _PickerList({
    required this.label,
    required this.options,
    required this.selected,
    required this.rowHeight,
    required this.fullPage,
    required this.animation,
    required this.scroll,
    required this.closingIndex,
    required this.panelOpacity,
    required this.onSelected,
    this.previewCandidate,
    required this.exitStart,
    required this.gesturePreview,
  });
  final int? previewCandidate;
  final double? Function() exitStart;
  final bool Function() gesturePreview;
  final String label;
  final List<String> options;
  final int selected;
  final double rowHeight;
  final bool fullPage;
  final Animation<double> animation;
  final ScrollController scroll;
  final int? Function() closingIndex;
  final double Function() panelOpacity;
  final ValueChanged<int> onSelected;
  @override
  State<_PickerList> createState() => _PickerListState();
}

class _PickerListState extends State<_PickerList> {
  final _focus = FocusNode();
  late int _candidate = widget.selected;
  bool _keyboard = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      widget.onSelected(_candidate);
      return KeyEventResult.handled;
    }
    int? next;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      next = _candidate - 1;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      next = _candidate + 1;
    }
    if (key == LogicalKeyboardKey.home) next = 0;
    if (key == LogicalKeyboardKey.end) next = widget.options.length - 1;
    if (next == null) return KeyEventResult.ignored;
    setState(() {
      _candidate = next!.clamp(0, widget.options.length - 1);
      _keyboard = true;
    });
    _focus.requestFocus();
    if (widget.scroll.hasClients) {
      final top = _candidate * widget.rowHeight + (widget.fullPage ? 16 : 0);
      final bottom = top + widget.rowHeight;
      final position = widget.scroll.position;
      final target =
          (top < position.pixels
                  ? top
                  : bottom > position.pixels + position.viewportDimension
                  ? bottom - position.viewportDimension
                  : position.pixels)
              .clamp(0.0, position.maxScrollExtent);
      widget.scroll.jumpTo(target);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _key,
    child: LayoutBuilder(
      builder: (c, bounds) => Stack(
        children: [
          ListView.builder(
            controller: widget.scroll,
            itemExtent: widget.rowHeight,
            padding: EdgeInsets.symmetric(
              horizontal: widget.fullPage ? 24 : 0,
              vertical: widget.fullPage ? 16 : 0,
            ),
            itemCount: widget.options.length,
            itemBuilder: (c, i) => AnimatedBuilder(
              animation: widget.animation,
              builder: (c, _) {
                final closing =
                    widget.animation.status == AnimationStatus.reverse;
                final reduced = c.brockmann.motionReduced(c);
                final exit = widget.exitStart();
                final preview = widget.gesturePreview();
                final first = widget.scroll.hasClients
                    ? (widget.scroll.offset / widget.rowHeight).floor()
                    : widget.selected;
                final stagger = (i - first).clamp(0, 6) * .03;
                final entry = exit ?? widget.animation.value;
                final f = !widget.fullPage || reduced || preview
                    ? 1.0
                    : Curves.easeOutCubic.transform(
                        ((entry * .48 - stagger) / .30).clamp(0, 1),
                      );
                final retreat =
                    widget.fullPage && !reduced && exit != null && !preview
                    ? 12 *
                          (1 -
                              Curves.easeInOutCubic.transform(
                                (widget.animation.value /
                                        math.max(.000001, exit))
                                    .clamp(0, 1),
                              ))
                    : 0.0;
                final hidden =
                    !widget.fullPage && closing && widget.closingIndex() == i;
                return Opacity(
                  opacity: hidden
                      ? 0
                      : widget.fullPage
                      ? f
                      : !closing && i == widget.selected
                      ? 1
                      : widget.panelOpacity(),
                  child: Transform.translate(
                    offset: Offset(
                      -(widget.fullPage ? 24 : 40) * (1 - f) + retreat,
                      0,
                    ),
                    child: MouseRegion(
                      onEnter: (_) {
                        if (_candidate != i || _keyboard) {
                          setState(() {
                            _candidate = i;
                            _keyboard = false;
                          });
                        }
                      },
                      child: BrockmannPressable(
                        label: widget.options[i],
                        selected: i == widget.selected,
                        onPressed: () => widget.onSelected(i),
                        builder: (c, pressed) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          color: pressed
                              ? c.brockmann.line.withValues(alpha: .3)
                              : null,
                          alignment: Alignment.centerLeft,
                          child: BrockmannText(
                            widget.options[i],
                            role: widget.fullPage
                                ? BrockmannType.heading
                                : BrockmannType.value,
                            color: i == widget.selected
                                ? c.brockmann.accentText
                                : c.brockmann.foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IgnorePointer(
            child: Opacity(
              opacity: _keyboard || widget.previewCandidate != null ? 1 : 0,
              child: BrockmannMotion(
                immediate: !_keyboard && widget.previewCandidate == null,
                value: (widget.previewCandidate ?? _candidate).toDouble(),
                milliseconds: 140,
                builder: (c, position) => AnimatedBuilder(
                  animation: widget.scroll,
                  builder: (c, _) => Stack(
                    children: [
                      Positioned(
                        left: widget.fullPage ? 28 : 4,
                        right: widget.fullPage ? 28 : 4,
                        top:
                            position * widget.rowHeight -
                            (widget.scroll.hasClients
                                ? widget.scroll.offset
                                : 0) +
                            (widget.fullPage ? 16 : 0) +
                            4,
                        height: widget.rowHeight - 8,
                        child: DecoratedBox(
                          key: const ValueKey('brockmann-picker-focus'),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: c.brockmann.accent,
                              width: 2,
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
        ],
      ),
    ),
  );
}

class _PickerClip extends CustomClipper<Rect> {
  const _PickerClip(this.rect);
  final Rect rect;
  @override
  Rect getClip(Size size) => rect;
  @override
  bool shouldReclip(_PickerClip old) => old.rect != rect;
}
