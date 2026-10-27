import 'package:flutter/material.dart';

import 'theme.dart';
import 'foundation.dart';
import 'interaction.dart';

/// Label and control share a 48 dp touch target. Null is a mixed value.
class BrockmannCheckbox extends StatelessWidget {
  const BrockmannCheckbox({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.compact = false,
  });
  final String label;
  final bool? value;
  final bool tristate, compact;
  final ValueChanged<bool?>? onChanged;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return MergeSemantics(
      child: Semantics(
        checked: value == true,
        mixed: value == null,
        child: BrockmannPressable(
          label: label,
          button: false,
          onPressed: onChanged == null
              ? null
              : () => onChanged!(
                  tristate
                      ? (value == false
                            ? true
                            : value == true
                            ? null
                            : false)
                      : value != true,
                ),
          builder: (c, p) => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                AnimatedContainer(
                  duration: t.duration(c, 160),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: value != false ? t.accent : Colors.transparent,
                    border: Border.all(
                      color: onChanged == null ? t.disabled : t.foreground,
                    ),
                  ),
                  child: value == false
                      ? null
                      : BrockmannGlyph(
                          value == null
                              ? BrockmannIcon.minus
                              : BrockmannIcon.check,
                          size: 16,
                          color: t.onAccent,
                        ),
                ),
                if (!compact) const SizedBox(width: 16),
                if (!compact)
                  Expanded(
                    child: BrockmannText(
                      label,
                      color: onChanged == null ? t.disabled : t.foreground,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BrockmannRadioGroup<T> extends StatelessWidget {
  const BrockmannRadioGroup({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.labelFor,
  });
  final String label;
  final List<T> options;
  final T? value;
  final ValueChanged<T>? onChanged;
  final String Function(T) labelFor;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrockmannText(label, role: BrockmannType.label, color: t.secondary),
        const SizedBox(height: 8),
        for (final option in options)
          Semantics(
            checked: value == option,
            inMutuallyExclusiveGroup: true,
            child: BrockmannPressable(
              label: labelFor(option),
              button: false,
              onPressed: onChanged == null ? null : () => onChanged!(option),
              builder: (c, p) => ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: onChanged == null ? t.disabled : t.foreground,
                        ),
                      ),
                      child: AnimatedContainer(
                        duration: t.duration(c, 160),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: value == option
                              ? t.accent
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: BrockmannText(labelFor(option))),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Wraps on small screens instead of clipping destinations.
class BrockmannSegmentedControl<T> extends StatelessWidget {
  const BrockmannSegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.labelFor,
  });
  final List<T> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final String Function(T) labelFor;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final option in options)
          Semantics(
            selected: option == value,
            child: BrockmannPressable(
              label: labelFor(option),
              onPressed: onChanged == null ? null : () => onChanged!(option),
              builder: (c, p) => AnimatedContainer(
                duration: t.duration(c, 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: option == value ? t.foreground : t.surface,
                  border: Border.all(
                    color: option == value ? t.foreground : t.line,
                  ),
                ),
                child: BrockmannText(
                  labelFor(option),
                  color: option == value ? t.background : t.foreground,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class BrockmannRangeSlider extends StatelessWidget {
  const BrockmannRangeSlider({
    super.key,
    required this.label,
    required this.values,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
  });
  final String label;
  final RangeValues values;
  final ValueChanged<RangeValues>? onChanged;
  final double min, max;
  final int? divisions;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrockmannText(label, role: BrockmannType.label, color: t.secondary),
        const SizedBox(height: 4),
        BrockmannText(
          '${values.start.toStringAsFixed(2)} – ${values.end.toStringAsFixed(2)}',
          role: BrockmannType.monoValue,
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: t.accent,
            inactiveTrackColor: t.line,
            thumbColor: t.foreground,
            overlayColor: t.foreground.withValues(alpha: .08),
            trackHeight: 3,
            rangeThumbShape: const _SquareRangeThumb(),
          ),
          child: BrockmannInteractionRegion(
            enabled: onChanged != null,
            child: BrockmannHandleFeedback(
              enabled: onChanged != null,
              isHandle: (p, size) {
                final width = size.width - 48;
                final a = 24 + (values.start - min) / (max - min) * width,
                    b = 24 + (values.end - min) / (max - min) * width;
                return (p.dx - a).abs() <= 24 || (p.dx - b).abs() <= 24;
              },
              child: RangeSlider(
                values: values,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SquareRangeThumb extends RangeSliderThumbShape {
  const _SquareRangeThumb();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(12, 28);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
    bool? isPressed,
  }) {
    context.canvas.drawRect(
      Rect.fromCenter(
        center: center,
        width: 12 + 8 * activationAnimation.value,
        height: 28 + 10 * activationAnimation.value,
      ),
      Paint()
        ..color = Color.lerp(
          sliderTheme.thumbColor!,
          sliderTheme.activeTrackColor!,
          activationAnimation.value,
        )!,
    );
  }
}

class BrockmannStepper extends StatelessWidget {
  const BrockmannStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
  });
  final String label;
  final double value, min, max, step;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrockmannText(label, role: BrockmannType.label),
            BrockmannText('$value', role: BrockmannType.monoValue),
          ],
        ),
      ),
      BrockmannIconButton(
        icon: BrockmannIcon.minus,
        label: 'Decrease $label',
        onPressed: onChanged == null || value <= min
            ? null
            : () => onChanged!((value - step).clamp(min, max)),
      ),
      BrockmannIconButton(
        icon: BrockmannIcon.plus,
        label: 'Increase $label',
        onPressed: onChanged == null || value >= max
            ? null
            : () => onChanged!((value + step).clamp(min, max)),
      ),
    ],
  );
}

class BrockmannChip extends StatelessWidget {
  const BrockmannChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onPressed,
    this.onDeleted,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed, onDeleted;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: selected ? t.foreground : t.line),
        color: selected ? t.surface : Colors.transparent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: BrockmannPressable(
              label: label,
              selected: selected,
              onPressed: onPressed,
              builder: (c, p) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: BrockmannText(label),
              ),
            ),
          ),
          if (onDeleted != null)
            BrockmannIconButton(
              icon: BrockmannIcon.x,
              label: 'Remove $label',
              onPressed: onDeleted,
            ),
        ],
      ),
    );
  }
}

class BrockmannAccordion extends StatelessWidget {
  const BrockmannAccordion({
    super.key,
    required this.title,
    required this.expanded,
    required this.onChanged,
    required this.child,
  });
  final String title;
  final bool expanded;
  final ValueChanged<bool> onChanged;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: expanded,
          child: BrockmannPressable(
            label: title,
            onPressed: () => onChanged(!expanded),
            builder: (c, p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: BrockmannText(title, role: BrockmannType.value),
                  ),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: t.duration(c, 180),
                    child: const BrockmannGlyph(BrockmannIcon.caretDown),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: t.duration(context, 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class BrockmannBadge extends StatelessWidget {
  const BrockmannBadge({super.key, required this.label, this.color});
  final String label;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    color: color ?? context.brockmann.surface,
    child: BrockmannText(label, role: BrockmannType.caption),
  );
}

class BrockmannEmptyState extends StatelessWidget {
  const BrockmannEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.action,
  });
  final String title, message;
  final BrockmannIcon? icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          BrockmannGlyph(icon!, size: 40),
          const SizedBox(height: 16),
        ],
        BrockmannText(title, role: BrockmannType.heading),
        const SizedBox(height: 8),
        BrockmannText(message, color: context.brockmann.secondary),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class BrockmannSearchField extends StatelessWidget {
  const BrockmannSearchField({
    super.key,
    required this.controller,
    this.label = 'search',
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (c, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        style: BrockmannType.heading.style(color: t.foreground),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: BrockmannType.label.style(color: t.secondary),
          prefixIcon: const Padding(
            padding: EdgeInsets.all(12),
            child: BrockmannGlyph(BrockmannIcon.search),
          ),
          suffixIcon: value.text.isEmpty
              ? null
              : BrockmannIconButton(
                  icon: BrockmannIcon.x,
                  label: 'Clear $label',
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
          border: UnderlineInputBorder(borderSide: BorderSide(color: t.line)),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: t.line),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: t.foreground),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class BrockmannBanner extends StatelessWidget {
  const BrockmannBanner({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.onClose,
  });
  final String title, message;
  final BrockmannIcon? icon;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    color: context.brockmann.surface,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[BrockmannGlyph(icon!), const SizedBox(width: 16)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrockmannText(title, role: BrockmannType.value),
              const SizedBox(height: 4),
              BrockmannText(message),
            ],
          ),
        ),
        if (onClose != null)
          BrockmannIconButton(
            icon: BrockmannIcon.x,
            label: 'Dismiss $title',
            onPressed: onClose,
          ),
      ],
    ),
  );
}

@immutable
class BrockmannDestination {
  const BrockmannDestination(this.label, this.icon);
  final String label;
  final BrockmannIcon icon;
}

class BrockmannNavigationBar extends StatelessWidget {
  const BrockmannNavigationBar({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onChanged,
  });
  final List<BrockmannDestination> destinations;
  final int selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.line)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < destinations.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == selected,
                  child: BrockmannPressable(
                    label: destinations[i].label,
                    onPressed: () => onChanged(i),
                    builder: (c, p) => AnimatedContainer(
                      duration: t.duration(c, 180),
                      color: i == selected ? t.surface : Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BrockmannGlyph(
                            destinations[i].icon,
                            color: i == selected ? t.foreground : t.secondary,
                          ),
                          const SizedBox(height: 4),
                          BrockmannText(
                            destinations[i].label,
                            role: BrockmannType.caption,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
