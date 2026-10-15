import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'app_haptics.dart';
import 'icons/campus_icon.dart';

class EditorialAction extends StatefulWidget {
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
  final bool filled;
  final bool outlined;
  final bool invertOnInteraction;
  final EdgeInsets padding;
  @override
  State<EditorialAction> createState() => _EditorialActionState();
}

class _EditorialActionState extends State<EditorialAction> {
  bool _active = false;
  bool _pressed = false;
  Offset? _pointerOrigin;

  void _release() {
    _pointerOrigin = null;
    if (_pressed) setState(() => _pressed = false);
  }

  void _activate() {
    if (widget.onPressed == null) return;
    AppHaptics.action(primary: widget.filled);
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = widget.onPressed != null;
    final inverted =
        widget.filled != (widget.invertOnInteraction && (_active || _pressed));
    final foreground = !enabled
        ? palette.muted
        : inverted
        ? palette.paper
        : palette.ink;
    return Semantics(
      onTap: enabled ? _activate : null,
      button: true,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _active = value),
        onShowHoverHighlight: (value) => setState(() => _active = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: Listener(
          onPointerDown: enabled
              ? (event) {
                  _pointerOrigin = event.position;
                  setState(() => _pressed = true);
                }
              : null,
          onPointerMove: (event) {
            if (_pointerOrigin != null &&
                (event.position - _pointerOrigin!).distance > 8) {
              _release();
            }
          },
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? _activate : null,
            onTapCancel: _release,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Duration(milliseconds: _pressed ? 60 : 120),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              padding: widget.padding,
              decoration: BoxDecoration(
                color: inverted && enabled
                    ? palette.ink
                    : !widget.invertOnInteraction && (_active || _pressed)
                    ? palette.selectionSurface
                    : palette.paper,
                border: widget.outlined || widget.filled
                    ? Border.all(
                        color: enabled ? palette.ink : palette.line,
                        width: .5,
                      )
                    : null,
              ),
              child: IconTheme(
                data: IconThemeData(color: foreground, size: 20),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    height: 1.4,
                    color: foreground,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => Semantics(
    checked: value == true,
    child: EditorialAction(
      onPressed: onChanged == null ? null : () => onChanged!(!(value ?? false)),
      padding: const EdgeInsets.all(14),
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value == true ? context.palette.ink : null,
          border: Border.all(color: context.palette.ink, width: .5),
        ),
        child: value == true
            ? CampusIcon(
                Icons.check_rounded,
                size: 16,
                color: context.palette.paper,
              )
            : null,
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
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: EditorialAction(
      invertOnInteraction: false,
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Container(
        width: 56,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: context.palette.ink, width: .5),
        ),
        child: AnimatedAlign(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 18, height: 20, color: context.palette.ink),
        ),
      ),
    ),
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
    height: compact ? 24 : strokeWidth,
    child: Center(
      child: LinearProgressIndicator(
        minHeight: strokeWidth,
        value: MediaQuery.disableAnimationsOf(context) ? value ?? .5 : value,
        color: color ?? context.palette.ink,
        backgroundColor: trackColor ?? context.palette.line,
        borderRadius: BorderRadius.zero,
      ),
    ),
  );
}

abstract final class CampusNotice {
  static void show(BuildContext context, {required String message}) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
