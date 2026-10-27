import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'feedback.dart';
import 'theme.dart';

/// Shared by the page switcher and regions whose pointers it must not claim.
class BrockmannGestureScope extends InheritedWidget {
  const BrockmannGestureScope({
    super.key,
    required this.pointers,
    required super.child,
  });
  final Set<int> pointers;
  static Set<int>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BrockmannGestureScope>()
      ?.pointers;
  @override
  bool updateShouldNotify(BrockmannGestureScope oldWidget) =>
      pointers != oldWidget.pointers;
}

/// A direct-manipulation surface owns gestures that begin inside it. Page
/// swipes remain available outside it, including ordinary page whitespace.
class BrockmannInteractionRegion extends StatelessWidget {
  const BrockmannInteractionRegion({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final pointers = BrockmannGestureScope.of(context);
    return Listener(
      onPointerDown: (e) => pointers?.add(e.pointer),
      onPointerPanZoomStart: (e) => pointers?.add(e.pointer),
      onPointerPanZoomEnd: (e) => pointers?.remove(e.pointer),
      onPointerUp: (e) => pointers?.remove(e.pointer),
      onPointerCancel: (e) => pointers?.remove(e.pointer),
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(gestureSettings: const DeviceGestureSettings(touchSlop: 2)),
        child: child,
      ),
    );
  }
}

/// Animated visual pickup plus one OS-respecting tactile response. No
/// continuous ticks, sound, or repeated impact during the same pointer gesture.
class BrockmannHandleFeedback extends StatefulWidget {
  const BrockmannHandleFeedback({
    super.key,
    this.child,
    this.builder,
    required this.isHandle,
    this.enabled = true,
  }) : assert(child != null || builder != null);
  final Widget? child;

  /// Receives the animated hold amount, from rest (0) to held (1).
  final Widget Function(BuildContext, double)? builder;
  final bool enabled;
  final bool Function(Offset local, Size size) isHandle;
  @override
  State<BrockmannHandleFeedback> createState() =>
      _BrockmannHandleFeedbackState();
}

class _BrockmannHandleFeedbackState extends State<BrockmannHandleFeedback>
    with SingleTickerProviderStateMixin {
  late final _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 80),
    reverseDuration: const Duration(milliseconds: 180),
  );
  Timer? _timer;
  Offset? _start;
  int? _pointer;
  bool _fired = false;
  void fire() {
    _timer?.cancel();
    if (_fired || !mounted) return;
    _fired = true;
    BrockmannFeedbackScope.of(context)?.gesture(lifting: true);
  }

  void end() {
    _timer?.cancel();
    _start = null;
    _pointer = null;
    _fired = false;
    _press.reverse();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: !widget.enabled
        ? null
        : (e) {
            if (_pointer != null) return;
            final box = context.findRenderObject() as RenderBox;
            if (!widget.isHandle(box.globalToLocal(e.position), box.size)) {
              return;
            }
            _press.duration = context.brockmann.duration(context, 80);
            _press.reverseDuration = context.brockmann.duration(context, 180);
            _press.forward();
            _pointer = e.pointer;
            _start = e.position;
            _fired = false;
            _timer = Timer(const Duration(milliseconds: 160), fire);
          },
    onPointerMove: (e) {
      if (e.pointer != _pointer || _start == null) return;
      final delta = e.position - _start!;
      if (!_fired && delta.dy.abs() > 8 && delta.dy.abs() > delta.dx.abs()) {
        _timer?.cancel();
        _start = null;
        _press.reverse();
      } else if (delta.dx.abs() > 8) {
        fire();
      }
    },
    onPointerUp: (e) {
      if (e.pointer == _pointer) end();
    },
    onPointerCancel: (e) {
      if (e.pointer == _pointer) end();
    },
    child: AnimatedBuilder(
      animation: _press,
      builder: (c, _) =>
          widget.builder?.call(c, Curves.easeOut.transform(_press.value)) ??
          widget.child!,
    ),
  );
}
