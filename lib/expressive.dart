import 'campus_design.dart';
import 'app_haptics.dart';
import 'l10n.dart';

import 'package:flutter/material.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/services.dart';

Future<T?> showExpressiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black.withValues(
    alpha: context.brockmann.light ? .4 : .6,
  ),
  transitionDuration: context.brockmann.duration(context, 160),
  pageBuilder: (context, _, _) =>
      PredictiveBackSurface(child: builder(context)),
  transitionBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
);

Future<T?> showExpressiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool compact = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  constraints: const BoxConstraints(maxWidth: double.infinity),
  backgroundColor: context.brockmann.surface,
  elevation: 0,
  shape: Border(top: BorderSide(color: context.brockmann.line)),
  sheetAnimationStyle: AnimationStyle(
    duration: context.brockmann.duration(context, 220),
    reverseDuration: context.brockmann.duration(context, 200),
  ),
  builder: (context) => PredictiveBackSurface(
    child: AnimatedPadding(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 48),
                Expanded(
                  child: Center(
                    child: showDragHandle
                        ? Container(
                            width: 32,
                            height: 2,
                            color: Theme.of(context).dividerColor,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                CampusTextAction(
                  icon: Icons.close_rounded,
                  label: tr(context, 'Закрыть', 'Close'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Flexible(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: compact
                      ? SingleChildScrollView(child: builder(context))
                      : builder(context),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

/// Route-backed picker with wrapped labels and native back handling.
class AppPassPicker extends StatelessWidget {
  const AppPassPicker({
    super.key,
    required this.items,
    required this.enabled,
    required this.hint,
    required this.onChanged,
  });
  final List<PassPickerItem<String>> items;
  final bool enabled;
  final String hint;
  final ValueChanged<List<PassPickerItem<String>>> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = items.indexWhere((item) => item.selected);
    if (items.any((item) => item.disabled)) {
      return BrockmannButton(
        label: selected < 0 ? hint : items[selected].label,
        onPressed: !enabled
            ? null
            : () async {
                final item =
                    await showBrockmannActionSheet<PassPickerItem<String>>(
                      context,
                      title: hint,
                      entries: [
                        for (final item in items)
                          BrockmannMenuEntry(
                            value: item,
                            label: item.label,
                            enabled: !item.disabled,
                          ),
                      ],
                    );
                if (context.mounted && item != null) {
                  AppHaptics.selection();
                  onChanged([item]);
                }
              },
      );
    }
    return BrockmannPicker(
      label: hint,
      options: [for (final item in items) item.label],
      selected: selected < 0 ? 0 : selected,
      onChanged: !enabled
          ? null
          : (index) {
              AppHaptics.selection();
              onChanged([items[index]]);
            },
    );
  }
}

/// Makes popup-route animations follow Android's back gesture, including cancel.
/// Pages use the theme's PredictiveBackPageTransitionsBuilder instead.
class PredictiveBackSurface extends StatefulWidget {
  const PredictiveBackSurface({super.key, required this.child});
  final Widget child;

  @override
  State<PredictiveBackSurface> createState() => _PredictiveBackSurfaceState();
}

class _PredictiveBackSurfaceState extends State<PredictiveBackSurface>
    with WidgetsBindingObserver {
  ModalRoute<dynamic>? _gestureRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    final route = ModalRoute.of(context);
    if (event.isButtonEvent ||
        route == null ||
        !route.isCurrent ||
        !route.popGestureEnabled ||
        Theme.of(context).platform != TargetPlatform.android) {
      return false;
    }
    _gestureRoute = route;
    route.handleStartBackGesture(progress: 1 - event.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    _gestureRoute?.handleUpdateBackGestureProgress(
      progress: 1 - event.progress,
    );
  }

  @override
  void handleCancelBackGesture() {
    _gestureRoute?.handleCancelBackGesture();
    _gestureRoute = null;
  }

  @override
  void handleCommitBackGesture() {
    _gestureRoute?.handleCommitBackGesture();
    _gestureRoute = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Brockmann command band with typed app actions and Android Back dismissal.
class AppActionMenu extends StatelessWidget {
  const AppActionMenu({
    super.key,
    required this.entries,
    required this.anchorBuilder,
    required this.onSelected,
  });
  final List<CampusMenuEntry> entries;
  final CampusMenuAnchorBuilder anchorBuilder;
  final ValueChanged<Object?> onSelected;

  @override
  Widget build(BuildContext context) => anchorBuilder(context, () async {
    final selected = await showBrockmannActionSheet<CampusMenuEntry>(
      context,
      title: tr(context, 'Управление', 'Manage'),
      entries: [
        for (final entry in entries)
          BrockmannMenuEntry(
            value: entry,
            label: entry.label,
            enabled: entry.enabled,
            leading: entry.leading,
            trailing: entry.trailing,
            secondary: entry.supportingText,
            destructive: entry.value == 'remove' || entry.value == 'delete',
          ),
      ],
    );
    if (selected != null && context.mounted) {
      selected.onPressed?.call();
      onSelected(selected.value);
    }
  });
}
