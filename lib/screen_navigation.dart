import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_haptics.dart';
import 'app_theme.dart';
import 'l10n.dart';
import 'screen_selector.dart';
import 'screens.dart';

class ScreenNavigation extends StatefulWidget {
  const ScreenNavigation({
    super.key,
    required this.selectorVisible,
    required this.selectedIndex,
    required this.onSelected,
    required this.onIndex,
    required this.child,
    this.debugVisible = false,
    this.onRevealDebug,
  });
  final bool selectorVisible;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onIndex;
  final Widget child;
  final bool debugVisible;
  final VoidCallback? onRevealDebug;

  @override
  State<ScreenNavigation> createState() => _ScreenNavigationState();
}

class _ScreenNavigationState extends State<ScreenNavigation>
    with TickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    value: widget.selectorVisible ? 0 : 1,
  );
  late final _arrival = AnimationController(vsync: this, value: 1);
  late final _pages = PageController(
    initialPage: _pageFor(widget.selectedIndex),
  )..addListener(_trackRail);
  late final _position = ValueNotifier<double>(
    _pageFor(widget.selectedIndex).toDouble(),
  );
  late int _detent = _pageFor(widget.selectedIndex);
  int _secretSwipes = 0;
  int? _secretPointer;
  Offset? _secretStart;

  // The developer screen, once revealed, sits above the first one.
  int get _pageCount => widget.debugVisible ? Screens.count + 1 : Screens.count;
  int _pageFor(int screen) => widget.debugVisible
      ? (screen == Screens.developer ? 0 : screen + 1)
      : screen;
  int _screenFor(int page) =>
      widget.debugVisible ? (page == 0 ? Screens.developer : page - 1) : page;

  void _pointerDown(PointerDownEvent event) {
    if (!widget.debugVisible &&
        !widget.selectorVisible &&
        widget.selectedIndex == 0 &&
        _position.value.abs() < .01 &&
        _secretPointer == null) {
      _secretPointer = event.pointer;
      _secretStart = event.position;
    } else {
      _secretPointer = null;
      _secretStart = null;
      _secretSwipes = 0;
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (_secretPointer != event.pointer || _secretStart == null) return;
    final delta = event.position - _secretStart!;
    _secretPointer = null;
    _secretStart = null;
    if (delta.dy >= 72 &&
        delta.dy > delta.dx.abs() * 1.4 &&
        widget.selectedIndex == 0 &&
        !widget.selectorVisible) {
      _secretSwipes++;
      if (_secretSwipes == 5) {
        _secretSwipes = 0;
        AppHaptics.navigation();
        widget.onRevealDebug?.call();
      }
    } else {
      _secretSwipes = 0;
    }
  }

  int _origin = 0;
  int? _pendingCommit;
  int? _railSelection;
  double _direction = 1;
  bool _dragging = false;
  bool _edgeFeedback = false;
  late final _contentMotion = Listenable.merge([_arrival, _position]);

  bool get _reduced => MediaQuery.disableAnimationsOf(context);
  Duration _time(int milliseconds) =>
      _reduced ? Duration.zero : Duration(milliseconds: milliseconds);

  @override
  void didUpdateWidget(ScreenNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectorVisible || widget.selectedIndex != 0) _secretSwipes = 0;
    if (oldWidget.debugVisible != widget.debugVisible) {
      _pendingCommit = null;
      _detent = _pageFor(widget.selectedIndex);
      _position.value = _detent.toDouble();
      if (_pages.hasClients) _pages.jumpToPage(_detent);
    }
    if (oldWidget.selectorVisible != widget.selectorVisible) {
      _origin = widget.selectedIndex;
      _pendingCommit = null;
      _dragging = false;
      _detent = _pageFor(widget.selectedIndex);
      _arrival.value = 1;
      if (_pages.hasClients) _pages.jumpToPage(_pageFor(widget.selectedIndex));
      final target = widget.selectorVisible ? 0.0 : 1.0;
      final fullDuration = widget.selectorVisible ? 260 : 320;
      final remaining = (fullDuration * (target - _motion.value).abs()).round();
      _motion.animateTo(
        target,
        duration: _time(remaining.clamp(40, fullDuration)),
        curve: Curves.easeOutCubic,
      );
    } else if (oldWidget.selectedIndex != widget.selectedIndex) {
      _pendingCommit = null;
      _direction =
          _pageFor(widget.selectedIndex) > _pageFor(oldWidget.selectedIndex)
          ? 1
          : -1;
      final fromRail = _railSelection == widget.selectedIndex;
      _railSelection = null;
      if (fromRail) {
        _arrival.value = 1;
      } else {
        _arrival.duration = _time(190);
        _arrival.forward(from: 0);
      }
      if (!fromRail &&
          _pages.hasClients &&
          (_pages.page! - _pageFor(widget.selectedIndex)).abs() > .01) {
        if (_reduced) {
          _pages.jumpToPage(_pageFor(widget.selectedIndex));
        } else {
          _pages.animateToPage(
            _pageFor(widget.selectedIndex),
            duration: _time(230),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  void _trackRail() {
    if (_pages.hasClients) {
      _position.value =
          _pages.page ?? _pageFor(widget.selectedIndex).toDouble();
    }
  }

  void _tick(int index) {
    if (index == _detent) return;
    _detent = index;
    if (!widget.selectorVisible) {
      AppHaptics.selection();
      if (_screenFor(index) != widget.selectedIndex) _commitRail(index);
    }
  }

  void _commitRail(int index, {bool snap = false}) {
    if (_pendingCommit == index) return;
    _pendingCommit = index;
    // Page notifications may arrive during layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingCommit != index) return;
      _pendingCommit = null;
      if (widget.selectorVisible || _position.value.round() != index) return;
      if (snap && _pages.hasClients) _pages.jumpToPage(index);
      final screen = _screenFor(index);
      if (widget.selectedIndex != screen) {
        _railSelection = screen;
        widget.onSelected(screen);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _scroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _dragging = notification.dragDetails != null;
      _edgeFeedback = false;
      if (_dragging) _arrival.value = 1;
    }
    if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        !_edgeFeedback &&
        notification.overscroll.abs() > 8) {
      _edgeFeedback = true;
      AppHaptics.navigation();
    }
    if (notification is ScrollEndNotification) {
      _dragging = false;
      final index = _position.value.round().clamp(0, _pageCount - 1);
      if (!widget.selectorVisible &&
          (_screenFor(index) != widget.selectedIndex ||
              (_reduced && (_position.value - index).abs() > .001)) &&
          _pendingCommit != index) {
        _commitRail(index, snap: _reduced);
      }
    }
    return false;
  }

  void _open(int index) {
    AppHaptics.navigation();
    _origin = index;
    widget.onSelected(index);
  }

  void _index() {
    AppHaptics.navigation();
    widget.onIndex();
  }

  void _step(int delta) {
    if (!_pages.hasClients || _dragging) return;
    final next = (_position.value.round() + delta).clamp(0, _pageCount - 1);
    if (next == _position.value.round()) return;
    if (_reduced) {
      _pages.jumpToPage(next);
    } else {
      _pages.animateToPage(
        next,
        duration: _time(230),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pages.removeListener(_trackRail);
    _pages.dispose();
    _position.dispose();
    _motion.dispose();
    _arrival.dispose();
    super.dispose();
  }

  Widget _rail(BuildContext context, List<String> labels) => Column(
    children: [
      SafeArea(
        bottom: false,
        child: SizedBox(
          height: 58,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 48),
            ),
            onPressed: _index,
            child: Text(
              tr(context, 'МЕНЮ', 'INDEX'),
              style: const TextStyle(fontSize: 9, letterSpacing: 0),
            ),
          ),
        ),
      ),
      Expanded(
        child: Semantics(
          label: labels[widget.selectedIndex],
          onIncrease: _pageFor(widget.selectedIndex) < _pageCount - 1
              ? () => _step(1)
              : null,
          onDecrease: _pageFor(widget.selectedIndex) > 0
              ? () => _step(-1)
              : null,
          child: Focus(
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _step(1);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _step(-1);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerUp: _pointerUp,
              onPointerCancel: (_) {
                _secretPointer = null;
                _secretStart = null;
                _secretSwipes = 0;
              },
              onPointerSignal: (event) {
                if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
                  GestureBinding.instance.pointerSignalResolver.register(
                    event,
                    (_) => _step(event.scrollDelta.dy > 0 ? 1 : -1),
                  );
                }
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: _scroll,
                child: PageView.builder(
                  key: const ValueKey('screen-rail'),
                  controller: _pages,
                  pageSnapping: false,
                  scrollDirection: Axis.vertical,
                  physics: _RailPhysics(
                    instant: _reduced,
                    parent: const ClampingScrollPhysics(),
                  ),
                  itemCount: _pageCount,
                  onPageChanged: _tick,
                  itemBuilder: (context, index) => RepaintBoundary(
                    child: SelectorLabel(
                      index: _screenFor(index) == Screens.developer
                          ? -1
                          : _screenFor(index),
                      label: labels[_screenFor(index)],
                      fontSize: 26,
                      topPadding: 0,
                      onPressed: _index,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final labels = Screens.labels(context);
    final rail = _rail(context, labels);
    final content = RepaintBoundary(
      child: SafeArea(left: false, child: widget.child),
    );
    return ColoredBox(
      color: context.palette.paper,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final railWidth = bounds.maxWidth < 360 ? 48.0 : 60.0;
          final travel = (bounds.maxHeight * .075).clamp(18.0, 64.0);
          return AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              final t = _motion.value;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  if (t < 1)
                    IgnorePointer(
                      key: const ValueKey('navigation-selector-layer'),
                      ignoring: !widget.selectorVisible,
                      child: Opacity(
                        opacity: 1 - t,
                        child: RepaintBoundary(
                          child: ScreenSelector(
                            hiddenIndex: t == 0 || _origin == Screens.developer
                                ? null
                                : _origin,
                            onSelected: _open,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    key: const ValueKey('navigation-content-layer'),
                    left: railWidth,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Offstage(
                      offstage: t == 0,
                      child: IgnorePointer(
                        ignoring: widget.selectorVisible,
                        child: ClipRect(
                          child: AnimatedBuilder(
                            animation: _contentMotion,
                            child: content,
                            builder: (context, content) {
                              final drag = _reduced || widget.selectorVisible
                                  ? 0.0
                                  : (_position.value -
                                            _pageFor(widget.selectedIndex))
                                        .clamp(-1.0, 1.0);
                              final arrival = Curves.easeOutCubic.transform(
                                _arrival.value,
                              );
                              final opening = 1 - t;
                              final displacement = _reduced
                                  ? 0.0
                                  : -drag * travel +
                                        _direction * (1 - arrival) * travel;
                              final fade =
                                  (t *
                                          (1 - drag.abs() * .6) *
                                          (.4 + .6 * arrival))
                                      .clamp(0.0, 1.0);
                              return Transform.translate(
                                key: const ValueKey(
                                  'navigation-content-motion',
                                ),
                                offset: Offset(opening * 28, displacement),
                                child: Transform.scale(
                                  scale: _reduced
                                      ? 1
                                      : 1 -
                                            .018 *
                                                (drag.abs() + (1 - arrival))
                                                    .clamp(0, 1),
                                  alignment: Alignment.centerLeft,
                                  child: Opacity(opacity: fade, child: content),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (t > 0 && t < 1 && _origin != Screens.developer)
                    Positioned(
                      key: const ValueKey('navigation-morph-layer'),
                      left: lerpDouble(
                        _origin * bounds.maxWidth / Screens.count,
                        0,
                        t,
                      ),
                      top: t * (58 + MediaQuery.paddingOf(context).top),
                      bottom: 0,
                      width: lerpDouble(
                        bounds.maxWidth / Screens.count,
                        railWidth,
                        t,
                      ),
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: context.palette.paper,
                          child: SelectorLabel(
                            index: _origin,
                            topPadding:
                                MediaQuery.paddingOf(context).top * (1 - t),
                            label: labels[_origin],
                            fontSize: lerpDouble(
                              (bounds.maxWidth / Screens.count * .74).clamp(
                                24,
                                132,
                              ),
                              26,
                              t,
                            )!,
                            onPressed: () {},
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    key: const ValueKey('navigation-rail-layer'),
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: railWidth,
                    child: Offstage(offstage: t < 1, child: rail),
                  ),
                  if (t > 0)
                    Positioned(
                      left: railWidth - .5,
                      top: 0,
                      bottom: 0,
                      width: .5,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: t,
                          child: ColoredBox(color: context.palette.line),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _RailPhysics extends PageScrollPhysics {
  const _RailPhysics({super.parent, this.instant = false});
  final bool instant;
  @override
  _RailPhysics applyTo(ScrollPhysics? ancestor) =>
      _RailPhysics(parent: buildParent(ancestor), instant: instant);
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => instant ? null : super.createBallisticSimulation(position, velocity);
  @override
  SpringDescription get spring =>
      const SpringDescription(mass: .7, stiffness: 420, damping: 34);
}
