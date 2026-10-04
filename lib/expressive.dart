import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

Future<T?> showExpressiveDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: builder,
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
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: compact
        ? SingleChildScrollView(child: builder(context))
        : builder(context),
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
    final item = await showModalBottomSheet<M3EDropdownItem<String>>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(hint, style: Theme.of(context).textTheme.titleLarge),
          ),
          for (final item in items)
            ListTile(
              title: Text(item.label),
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
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: enabled ? () => _open(context) : null,
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
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
