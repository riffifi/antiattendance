import 'campus_design.dart';
import 'app_haptics.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';

import 'package:flutter/material.dart';
import 'package:brockmann/brockmann.dart';

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
      BrockmannModalTransition(animation: animation, child: child),
);

Future<T?> showExpressiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
  bool compact = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  constraints: const BoxConstraints(maxWidth: double.infinity),
  backgroundColor: context.brockmann.surface,
  elevation: 0,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
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
            if (showDragHandle) const SizedBox.shrink(),
            Align(
              alignment: Alignment.centerRight,
              child: CampusTextAction(
                label: tr(context, 'Закрыть', 'Close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Flexible(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
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

class ChoiceOption<T> {
  const ChoiceOption({
    required this.value,
    required this.label,
    this.supporting,
    this.selected = false,
    this.enabled = true,
  });
  final T value;
  final String label;
  final String? supporting;
  final bool selected, enabled;
}

/// Full-page Windows Phone choice list. Back returns null.
Future<T?> showChoicePage<T>(
  BuildContext context, {
  required String title,
  String? detail,
  required List<ChoiceOption<T>> options,
}) => Navigator.of(context).push<T>(
  MaterialPageRoute(
    builder: (context) => CampusScaffold(
      appBar: CampusAppBar(title: Text(title.toLowerCase())),
      body: ListView(
        padding: AaPageLayout.insets(context),
        children: [
          if (detail != null) ...[
            BrockmannText(detail),
            const SizedBox(height: 12),
          ],
          for (final option in options)
            CampusListItem(
              showDivider: false,
              headline: option.label,
              supportingText: option.supporting,
              trailing: option.selected
                  ? BrockmannGlyph(
                      BrockmannIcon.check,
                      size: 20,
                      color: context.brockmann.accent,
                    )
                  : null,
              onTap: option.enabled
                  ? () => Navigator.pop(context, option.value)
                  : null,
            ),
        ],
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
                            trailing: item.selected
                                ? BrockmannGlyph(
                                    BrockmannIcon.check,
                                    size: 20,
                                    color: context.brockmann.accent,
                                  )
                                : null,
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
typedef PredictiveBackSurface = BrockmannPredictiveBackSurface;

/// Brockmann command band with typed app actions and Android Back dismissal.
class AppActionMenu extends StatelessWidget {
  const AppActionMenu({
    super.key,
    required this.entries,
    this.title,
    required this.anchorBuilder,
    required this.onSelected,
  });
  final List<CampusMenuEntry> entries;
  final String? title;
  final CampusMenuAnchorBuilder anchorBuilder;
  final ValueChanged<Object?> onSelected;

  @override
  Widget build(BuildContext context) => anchorBuilder(context, () async {
    final options = [
      for (final entry in entries)
        ChoiceOption(
          value: entry,
          label: entry.label,
          supporting: entry.supportingText,
          enabled: entry.enabled,
        ),
    ];
    final selected = context.brockmann.windowsPhone
        ? await showChoicePage<CampusMenuEntry>(
            context,
            title: title ?? tr(context, 'управление', 'manage'),
            options: options,
          )
        : await showBrockmannActionSheet<CampusMenuEntry>(
            context,
            title: title ?? tr(context, 'управление', 'manage'),
            entries: [
              for (final entry in options)
                BrockmannMenuEntry(
                  value: entry.value,
                  label: entry.label,
                  enabled: entry.enabled,
                  leading: entry.value.leading,
                  trailing: entry.value.trailing,
                  secondary: entry.supporting,
                  destructive:
                      entry.value.value == 'remove' ||
                      entry.value.value == 'delete',
                ),
            ],
          );
    if (selected != null && context.mounted) {
      selected.onPressed?.call();
      onSelected(selected.value);
    }
  });
}
