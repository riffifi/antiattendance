import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

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
  showDragHandle: showDragHandle,
  builder: (context) => PredictiveBackSurface(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: compact
          ? SingleChildScrollView(child: builder(context))
          : builder(context),
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
  final List<M3EDropdownItem<String>> items;
  final bool enabled;
  final String hint;
  final ValueChanged<List<M3EDropdownItem<String>>> onChanged;

  Future<void> _open(BuildContext context) async {
    final item = await showExpressiveSheet<M3EDropdownItem<String>>(
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
            M3EListItem(
              headline: item.label,
              selected: item.selected,
              trailing: item.selected ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, item),
            ),
        ],
      ),
    );
    if (item != null && context.mounted) onChanged([item]);
  }

  @override
  Widget build(BuildContext context) => M3EButton.outlined(
    onPressed: enabled ? () => _open(context) : null,
    child: Row(
      children: [
        Expanded(
          child: Text(
            items.where((item) => item.selected).firstOrNull?.label ?? hint,
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.unfold_more_rounded, size: 20),
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
  final List<M3EMenuEntry> entries;
  final M3EMenuAnchorBuilder anchorBuilder;
  final ValueChanged<Object?> onSelected;

  @override
  Widget build(BuildContext context) => M3EMenu.entries(
    entries: entries,
    anchorBuilder: anchorBuilder,
    onSelected: onSelected,
    position: M3EMenuAnchorPosition.bottomEnd,
  );
}
