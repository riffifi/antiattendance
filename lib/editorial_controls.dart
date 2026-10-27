import 'package:flutter/material.dart';
import 'package:brockmann/brockmann.dart';

import 'app_haptics.dart';
import 'icons/campus_icon.dart';

/// App callback/semantic adapter over Brockmann's shared input foundation.
class EditorialAction extends StatelessWidget {
  const EditorialAction({
    super.key,
    required this.child,
    this.onPressed,
    this.filled = false,
    this.outlined = false,
    this.invertOnInteraction = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });
  final Widget child;
  final VoidCallback? onPressed;
  final bool filled, outlined, invertOnInteraction;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => BrockmannPressable(
    label: '',
    excludeSemantics: false,
    onPressed: onPressed == null
        ? null
        : () {
            AppHaptics.action(primary: filled);
            onPressed!();
          },
    builder: (context, pressed) {
      final t = context.brockmann;
      final foreground = onPressed == null
          ? t.disabled
          : filled
          ? t.onAccent
          : t.foreground;
      return AnimatedContainer(
        duration: t.duration(context, pressed ? 60 : 160),
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        padding: padding,
        decoration: BoxDecoration(
          color: filled && onPressed != null
              ? Color.lerp(t.accent, t.onAccent, pressed ? .12 : 0)
              : pressed
              ? t.surface
              : Colors.transparent,
          border: outlined
              ? Border.all(color: onPressed == null ? t.line : t.lineStrong)
              : null,
        ),
        child: IconTheme(
          data: IconThemeData(color: foreground, size: 20),
          child: DefaultTextStyle.merge(
            style: BrockmannType.body.style(color: foreground),
            child: child,
          ),
        ),
      );
    },
  );
}

class CampusTextAction extends StatelessWidget {
  const CampusTextAction({
    super.key,
    required this.label,
    this.icon,
    this.tooltip,
    this.onPressed,
  });
  final String label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: icon == null ? 96 : 48),
    child: Tooltip(
      message: tooltip ?? label,
      child: Semantics(
        label: tooltip ?? label,
        child: EditorialAction(
          onPressed: onPressed,
          invertOnInteraction: false,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ExcludeSemantics(
              child: icon != null
                  ? CampusIcon(icon, size: 20)
                  : Text(
                      label.toLowerCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

class CampusCheckbox extends StatelessWidget {
  const CampusCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Center(
      child: BrockmannCheckbox(
        label: '',
        compact: true,
        value: value,
        onChanged: onChanged == null
            ? null
            : (value) {
                AppHaptics.selection();
                onChanged!(value);
              },
      ),
    ),
  );
}

class CampusRadio<T> extends StatelessWidget {
  const CampusRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    child: CampusCheckbox(
      value: value == groupValue,
      onChanged: onChanged == null ? null : (_) => onChanged!(value),
    ),
  );
}

class CampusSwitch extends StatelessWidget {
  const CampusSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;
  @override
  Widget build(BuildContext context) => BrockmannSwitch(
    label: '',
    compact: true,
    value: value,
    sound: false,
    onChanged: onChanged == null
        ? null
        : (value) {
            AppHaptics.selection();
            onChanged!(value);
          },
  );
}

class CampusProgress extends StatelessWidget {
  const CampusProgress.linear({
    super.key,
    this.value,
    this.strokeWidth = 2,
    this.color,
    this.trackColor,
  }) : compact = false;
  const CampusProgress.compact({
    super.key,
    this.value,
    this.strokeWidth = 2,
    this.color,
    this.trackColor,
  }) : compact = true;
  final Color? color;
  final Color? trackColor;
  final double? value;
  final double strokeWidth;
  final bool compact;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: compact ? 24 : null,
    height: compact ? 24 : 16,
    child: Center(
      child: BrockmannProgress(label: '', value: value),
    ),
  );
}

abstract final class CampusNotice {
  static void show(BuildContext context, {required String message}) {
    showBrockmannToast(context, message);
  }
}
