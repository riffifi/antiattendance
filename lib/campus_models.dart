import 'package:material_ui/material_ui.dart';

enum CampusButtonStyle { filled, tonal, outlined, text }

class PassPickerItem<T> {
  const PassPickerItem({
    required this.value,
    required this.label,
    this.selected = false,
    this.disabled = false,
  });
  final T value;
  final String label;
  final bool selected;
  final bool disabled;
}

class CampusMenuEntry {
  const CampusMenuEntry({
    required this.label,
    this.value,
    this.leading,
    this.trailing,
    this.supportingText,
    this.onPressed,
    this.enabled = true,
  });
  final String label;
  final Object? value;
  final Widget? leading;
  final Widget? trailing;
  final String? supportingText;
  final VoidCallback? onPressed;
  final bool enabled;
}

typedef CampusMenuAnchorBuilder = Widget Function(
  BuildContext context,
  VoidCallback open,
);
