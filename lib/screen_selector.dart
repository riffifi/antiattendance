import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'screens.dart';

/// The entry point is a row of full-height typographic destinations.
class ScreenSelector extends StatelessWidget {
  const ScreenSelector({super.key, required this.onSelected, this.hiddenIndex});

  final ValueChanged<int> onSelected;
  final int? hiddenIndex;

  @override
  Widget build(BuildContext context) {
    final labels = Screens.labels(context).take(Screens.count).toList();
    return ColoredBox(
      color: context.palette.paper,
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
                    fontSize: (bounds.maxWidth / labels.length * .74).clamp(
                      24.0,
                      132.0,
                    ),
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
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final active = _hovered || _focused || _pressed;
    final foreground = active ? palette.paper : palette.ink;
    final padding = MediaQuery.paddingOf(context);
    return Semantics(
      button: true,
      enabled: true,
      onTap: widget.onPressed,
      label: widget.label,
      excludeSemantics: true,
      child: Material(
        color: active ? palette.ink : palette.paper,
        child: InkWell(
          onTap: widget.onPressed,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: widget.index == 0
                  ? null
                  : Border(left: BorderSide(color: palette.line, width: .5)),
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
                  Text(
                    '0${widget.index + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'GeistMono',
                      fontSize: 11,
                      letterSpacing: 1,
                      color: active ? foreground : palette.muted,
                    ),
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
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: widget.fontSize,
                              fontWeight: FontWeight.w300,
                              height: 1,
                              letterSpacing: -widget.fontSize * .045,
                              color: foreground,
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
        ),
      ),
    );
  }
}
