import 'package:flutter/material.dart';
import 'package:brockmann/brockmann.dart';

import 'l10n.dart';

/// The entry point is four full-height typographic destinations.
class ScreenSelector extends StatelessWidget {
  const ScreenSelector({super.key, required this.onSelected, this.hiddenIndex});

  final ValueChanged<int> onSelected;
  final int? hiddenIndex;

  @override
  Widget build(BuildContext context) {
    final labels = [
      tr(context, 'Посещаемость', 'Attendance'),
      tr(context, 'Расписание', 'Schedule'),
      tr(context, 'Пропуска', 'Passes'),
      tr(context, 'Настройки', 'Settings'),
    ];
    return ColoredBox(
      color: context.brockmann.background,
      child: LayoutBuilder(
        builder: (context, bounds) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < labels.length; index++)
              Expanded(
                child: Opacity(
                  opacity: hiddenIndex == index ? 0 : 1,
                  child: SelectorLabel(
                    key: ValueKey('screen-selector-$index'),
                    index: index,
                    label: labels[index],
                    fontSize: (bounds.maxWidth / 4 * .74).clamp(28.0, 132.0),
                    onPressed: () => onSelected(index),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SelectorLabel extends StatefulWidget {
  const SelectorLabel({
    super.key,
    required this.index,
    required this.label,
    required this.fontSize,
    required this.onPressed,
    this.topPadding,
  });

  final int index;
  final String label;
  final double fontSize;
  final VoidCallback onPressed;
  final double? topPadding;

  @override
  State<SelectorLabel> createState() => _SelectorLabelState();
}

class _SelectorLabelState extends State<SelectorLabel> {
  @override
  Widget build(BuildContext context) => BrockmannPressable(
    label: widget.label,
    onPressed: widget.onPressed,
    builder: (context, pressed) {
      final t = context.brockmann;
      final foreground = pressed ? t.background : t.foreground;
      final padding = MediaQuery.paddingOf(context);
      return ColoredBox(
        color: pressed ? t.foreground : t.background,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: widget.index == 0
                ? null
                : Border(left: BorderSide(color: t.line, width: .5)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              (widget.topPadding ?? padding.top) + 24,
              12,
              padding.bottom + 28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrockmannText(
                  '0${widget.index + 1}',
                  role: BrockmannType.monoValue,
                  color: pressed ? foreground : t.secondary,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.label.toUpperCase(),
                          maxLines: 1,
                          style: BrockmannType.title
                              .style(color: foreground)
                              .copyWith(
                                fontSize: widget.fontSize,
                                height: 1,
                                letterSpacing: -widget.fontSize * .045,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
