import 'campus_design.dart';
import 'app_haptics.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

Future<T?> showExpressiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (context) => PredictiveBackSurface(child: builder(context)),
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
  builder: (context) => PredictiveBackSurface(
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: compact
            ? SingleChildScrollView(child: builder(context))
            : builder(context),
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

  Future<void> _open(BuildContext context) async {
    AppHaptics.selection();
    final item = await showExpressiveSheet<PassPickerItem<String>>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(hint, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final item in items)
            CampusListItem(
              headline: item.label,
              selected: item.selected,
              trailing: item.selected ? const Text('×') : null,
              onTap: item.disabled ? null : () => Navigator.pop(context, item),
            ),
        ],
      ),
    );
    if (item != null && context.mounted) onChanged([item]);
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: enabled ? () => _open(context) : null,
    child: Row(
      children: [
        Expanded(
          child: Text(
            items.where((item) => item.selected).firstOrNull?.label ?? hint,
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
  );
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

/// Shared Expressive action menu with anchored motion and back dismissal.
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
    final selected = await showExpressiveSheet<CampusMenuEntry>(
      context: context,
      compact: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in entries)
              CampusListItem(
                headline: entry.label,
                supportingText: entry.supportingText,
                leading: entry.leading,
                trailing: entry.trailing,
                onTap: entry.enabled
                    ? () => Navigator.pop(context, entry)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      selected.onPressed?.call();
      onSelected(selected.value);
    }
  });
}
