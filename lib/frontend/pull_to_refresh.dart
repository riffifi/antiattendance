import 'dart:async';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import '../app_haptics.dart';
import '../l10n.dart';

/// Flutter owns the gesture and refresh lifecycle; AA supplies the indicator.
class CampusRefresh extends StatefulWidget {
  const CampusRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });
  final RefreshCallback onRefresh;
  final Widget child;
  @override
  State<CampusRefresh> createState() => _CampusRefreshState();
}

class _CampusRefreshState extends State<CampusRefresh> {
  RefreshIndicatorStatus? _status;
  double _pull = 0;
  Timer? _hide;

  void _changed(RefreshIndicatorStatus? status) {
    if (!mounted || status == _status) return;
    _hide?.cancel();
    if (status == RefreshIndicatorStatus.armed && _status != status) {
      AppHaptics.selection();
    }
    setState(() {
      _status = status;
      if (status == null || status == RefreshIndicatorStatus.canceled) {
        _pull = 0;
      }
    });
    if (status == RefreshIndicatorStatus.done ||
        status == RefreshIndicatorStatus.canceled) {
      _hide = Timer(
        context.brockmann.motionReduced(context)
            ? Duration.zero
            : context.brockmann.duration(context, 140),
        () => _changed(null),
      );
    }
  }

  Future<void> _refresh() async {
    // Flutter's noSpinner callback omits the refresh transition on this SDK.
    _changed(RefreshIndicatorStatus.refresh);
    await widget.onRefresh();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  bool _dragged(ScrollNotification event) {
    if (event.depth != 0 ||
        event.metrics.axis != Axis.vertical ||
        _status != RefreshIndicatorStatus.drag) {
      return false;
    }
    final overscroll = event.metrics.minScrollExtent - event.metrics.pixels;
    if (overscroll > 0) {
      setState(() => _pull = overscroll);
    } else if (event is OverscrollNotification && event.overscroll < 0) {
      setState(() => _pull -= event.overscroll);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final armed = _status == RefreshIndicatorStatus.armed;
    final refreshing =
        _status == RefreshIndicatorStatus.refresh ||
        _status == RefreshIndicatorStatus.snap ||
        _status == RefreshIndicatorStatus.done;
    final visible =
        armed || refreshing || _status == RefreshIndicatorStatus.drag;
    final factor =
        armed ||
            (_status == RefreshIndicatorStatus.refresh ||
                _status == RefreshIndicatorStatus.snap)
        ? 1.0
        : _status == RefreshIndicatorStatus.drag
        ? (_pull / 120).clamp(0.0, .85)
        : 0.0;
    final label = refreshing
        ? tr(context, 'Обновляем…', 'Refreshing…')
        : armed
        ? tr(context, 'Отпустите, чтобы обновить', 'Release to refresh')
        : tr(context, 'Потяните, чтобы обновить', 'Pull to refresh');
    final duration = t.motionReduced(context)
        ? Duration.zero
        : t.duration(context, 140);
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _dragged,
          child: RefreshIndicator.noSpinner(
            onRefresh: _refresh,
            onStatusChange: _changed,
            semanticsLabel: tr(context, 'Обновить', 'Refresh'),
            elevation: 0,
            child: widget.child,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: ExcludeSemantics(
              excluding: !visible,
              child: Semantics(
                liveRegion: true,
                label: label,
                child: ExcludeSemantics(
                  child: ClipRect(
                    child: AnimatedAlign(
                      alignment: Alignment.topCenter,
                      heightFactor: factor,
                      duration: _status == RefreshIndicatorStatus.drag
                          ? Duration.zero
                          : duration,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.background,
                          border: Border(bottom: BorderSide(color: t.line)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Opacity(
                                    opacity: refreshing ? 0 : 1,
                                    child: AnimatedRotation(
                                      turns: armed ? .5 : 0,
                                      duration: duration,
                                      child: BrockmannGlyph(
                                        BrockmannIcon.arrowDown,
                                        size: 16,
                                        color: t.accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: BrockmannText(
                                      label,
                                      role: BrockmannType.caption,
                                      color: t.foreground,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (_status == RefreshIndicatorStatus.refresh)
                                BrockmannProgress(label: label)
                              else
                                const SizedBox(height: 16),
                            ],
                          ),
                        ),
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
  }
}
