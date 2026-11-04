import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'app_haptics.dart';
import 'campus_design.dart';
import 'l10n.dart';

/// Shared Brockmann application frame: a pivot on phones, a list on tablets.
/// The body keeps its identity across navigation and window-size changes.
class ScreenNavigation extends StatefulWidget {
  const ScreenNavigation({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.child,
    this.debugVisible = false,
    this.onRevealDebug,
  });
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;
  final bool debugVisible;
  final VoidCallback? onRevealDebug;

  @override
  State<ScreenNavigation> createState() => _ScreenNavigationState();
}

class _ScreenNavigationState extends State<ScreenNavigation> {
  int _pulls = 0;
  double _distance = 0;

  void _select(int index) {
    _pulls = 0;
    if (index == widget.selectedIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    AppHaptics.selection();
    widget.onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final destinations = [
      tr(context, 'Посещаемость', 'Attendance'),
      tr(context, 'Расписание', 'Schedule'),
      tr(context, 'Пропуска', 'Passes'),
      tr(context, 'Настройки', 'Settings'),
      if (widget.debugVisible) tr(context, 'Разработчик', 'Developer'),
    ];
    return BrockmannAdaptiveScaffold(
      titleWidget: const Align(
        alignment: Alignment.centerLeft,
        child: CampusBrand(width: 48, height: 24),
      ),
      destinations: destinations,
      selected: widget.selectedIndex,
      onChanged: _select,
      actions: [
        GestureDetector(
          key: const ValueKey('app-diagnostics-gesture'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _distance = 0,
          onVerticalDragUpdate: (event) => _distance += event.delta.dy,
          onVerticalDragCancel: () => _pulls = 0,
          onVerticalDragEnd: (_) {
            if (_distance >= 80 &&
                widget.selectedIndex == 0 &&
                !widget.debugVisible) {
              if (++_pulls == 5) {
                _pulls = 0;
                widget.onRevealDebug?.call();
              }
            } else {
              _pulls = 0;
            }
          },
          child: const SizedBox(width: 48, height: 48),
        ),
      ],
      body: widget.child,
    );
  }
}
