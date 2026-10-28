import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'foundation.dart';
import 'motion.dart';
import 'navigation.dart';

/// The 4 dp rhythm, grouped in 8 and 16 dp steps.
abstract final class BrockmannSpace {
  static const double xxs = 4, xs = 8, s = 12, m = 16, l = 24, xl = 32;
  static const double xxl = 48, xxxl = 64;
}

/// Window classes measured in logical pixels of available width.
enum BrockmannWindowSize {
  /// Phones in portrait, below 600 dp.
  compact,

  /// Large phones in landscape, small tablets and split screens: 600–839 dp.
  medium,

  /// Tablets and desktop windows: 840–1199 dp.
  expanded,

  /// Wide desktop windows: 1200 dp and above.
  large;

  static BrockmannWindowSize of(double width) => width < 600
      ? compact
      : width < 840
      ? medium
      : width < 1200
      ? expanded
      : large;

  bool get isCompact => this == compact;
  bool operator >=(BrockmannWindowSize other) => index >= other.index;
  bool operator <(BrockmannWindowSize other) => index < other.index;
}

/// Layout metrics derived from an available width. Read the window metrics
/// with `context.brockmannLayout`, or wrap a region in [BrockmannResponsive]
/// for metrics based on that region's own width.
@immutable
class BrockmannLayout {
  const BrockmannLayout._(this.width, this.windowSize);
  factory BrockmannLayout.forWidth(double width) =>
      BrockmannLayout._(width, BrockmannWindowSize.of(width));
  final double width;
  final BrockmannWindowSize windowSize;

  bool get isCompact => windowSize.isCompact;
  bool get isWide => windowSize >= BrockmannWindowSize.expanded;

  /// Content starts 24 dp from the edge on phones and 48 dp on wider layouts.
  double get inset => width < 600 ? 24 : 48;

  /// Space between grid columns and panes.
  double get gutter => isCompact ? 16 : 24;

  /// A 4/8/12 column grid, by window class.
  int get columns => switch (windowSize) {
    BrockmannWindowSize.compact => 4,
    BrockmannWindowSize.medium => 8,
    _ => 12,
  };

  /// Chooses a value per window class; missing classes fall back to the next
  /// smaller one that was supplied.
  T value<T>({required T compact, T? medium, T? expanded, T? large}) =>
      switch (windowSize) {
        BrockmannWindowSize.compact => compact,
        BrockmannWindowSize.medium => medium ?? compact,
        BrockmannWindowSize.expanded => expanded ?? medium ?? compact,
        BrockmannWindowSize.large => large ?? expanded ?? medium ?? compact,
      };
}

extension BrockmannLayoutContext on BuildContext {
  /// Metrics for the whole window. Rebuilds only when the window size changes.
  BrockmannLayout get brockmannLayout =>
      BrockmannLayout.forWidth(MediaQuery.sizeOf(this).width);
}

/// Builds from the width this widget is given, not the window width, so a
/// component adapts correctly inside a pane, a dialog or a split screen.
class BrockmannResponsive extends StatelessWidget {
  const BrockmannResponsive({super.key, required this.builder});

  /// Convenience form that picks a child per window class.
  factory BrockmannResponsive.choose({
    Key? key,
    required Widget compact,
    Widget? medium,
    Widget? expanded,
    Widget? large,
  }) => BrockmannResponsive(
    key: key,
    builder: (_, layout) => layout.value(
      compact: compact,
      medium: medium,
      expanded: expanded,
      large: large,
    ),
  );
  final Widget Function(BuildContext context, BrockmannLayout layout) builder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => builder(
      context,
      BrockmannLayout.forWidth(
        c.hasBoundedWidth ? c.maxWidth : MediaQuery.sizeOf(context).width,
      ),
    ),
  );
}

/// A square gap that works in rows, columns and flexes alike.
class BrockmannGap extends StatelessWidget {
  const BrockmannGap(this.size, {super.key});
  const BrockmannGap.xs({super.key}) : size = BrockmannSpace.xs;
  const BrockmannGap.s({super.key}) : size = BrockmannSpace.s;
  const BrockmannGap.m({super.key}) : size = BrockmannSpace.m;
  const BrockmannGap.l({super.key}) : size = BrockmannSpace.l;
  const BrockmannGap.xl({super.key}) : size = BrockmannSpace.xl;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

/// A vertical stack with consistent spacing, so screens need no hand-placed
/// `SizedBox` between every child.
class BrockmannStack extends StatelessWidget {
  const BrockmannStack({
    super.key,
    required this.children,
    this.spacing = BrockmannSpace.l,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });
  final List<Widget> children;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: crossAxisAlignment,
    spacing: spacing,
    children: children,
  );
}

/// Limits line length on wide screens and centres the result. Phones are
/// unaffected. Use [inset] to add the adaptive 24/48 dp page margin.
class BrockmannContent extends StatelessWidget {
  const BrockmannContent({
    super.key,
    required this.child,
    this.maxWidth = 960,
    this.inset = false,
    this.alignment = Alignment.topCenter,
  });
  final Widget child;
  final double maxWidth;
  final bool inset;
  final AlignmentGeometry alignment;
  @override
  Widget build(BuildContext context) {
    Widget result = Align(
      alignment: alignment,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
    if (inset) {
      result = Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.brockmannLayout.inset,
        ),
        child: result,
      );
    }
    return result;
  }
}

/// Flows children into as many equal columns as fit. Each item is at least
/// [minItemWidth] wide (scaled with the user's text size), and the column
/// count can be capped with [maxColumns]. Rows size to their content, so
/// enlarged text never clips.
class BrockmannGrid extends StatelessWidget {
  const BrockmannGrid({
    super.key,
    required this.children,
    this.minItemWidth = 160,
    this.maxColumns,
    this.spacing = BrockmannSpace.m,
    this.runSpacing,
  });
  final List<Widget> children;
  final double minItemWidth, spacing;
  final double? runSpacing;
  final int? maxColumns;

  static int columnsFor(
    double width,
    double minItemWidth,
    double spacing, [
    int? maxColumns,
  ]) {
    final count = ((width + spacing) / (minItemWidth + spacing)).floor();
    return count.clamp(1, maxColumns ?? 1 << 20);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final minimum = minItemWidth * math.max(1, math.min(scale, 2));
      final columns = columnsFor(c.maxWidth, minimum, spacing, maxColumns);
      final width = ((c.maxWidth - spacing * (columns - 1)) / columns)
          .floorToDouble();
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing ?? spacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// Places panes side by side when there is room and stacks them otherwise.
/// [flex] gives each pane's share when side by side.
class BrockmannColumns extends StatelessWidget {
  const BrockmannColumns({
    super.key,
    required this.children,
    this.flex,
    this.breakpoint = 600,
    this.spacing,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  }) : assert(flex == null || flex.length == children.length);
  final List<Widget> children;
  final List<int>? flex;
  final double breakpoint;
  final double? spacing;
  final CrossAxisAlignment crossAxisAlignment;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final gap = spacing ?? (c.maxWidth < 600 ? 24.0 : 32.0);
      if (c.maxWidth < breakpoint) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: children,
        );
      }
      return Row(
        crossAxisAlignment: crossAxisAlignment,
        spacing: gap,
        children: [
          for (var i = 0; i < children.length; i++)
            Expanded(flex: flex?[i] ?? 1, child: children[i]),
        ],
      );
    },
  );
}

/// A hairline rule. Use instead of shadows to separate regions.
class BrockmannDivider extends StatelessWidget {
  const BrockmannDivider({
    super.key,
    this.axis = Axis.horizontal,
    this.strong = false,
    this.indent = 0,
  });
  final Axis axis;
  final bool strong;
  final double indent;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final line = ColoredBox(color: strong ? t.lineStrong : t.line);
    return axis == Axis.horizontal
        ? Padding(
            padding: EdgeInsetsDirectional.only(start: indent),
            child: SizedBox(height: 1, width: double.infinity, child: line),
          )
        : Padding(
            padding: EdgeInsets.only(top: indent),
            child: SizedBox(width: 1, height: double.infinity, child: line),
          );
  }
}

/// A titled group of content with an optional description and action.
/// Children are spaced on the 8 dp rhythm and enter with the row feather
/// when [feather] is set.
class BrockmannSection extends StatelessWidget {
  const BrockmannSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.trailing,
    this.spacing = BrockmannSpace.l,
    this.feather = false,
  });
  final String title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;
  final double spacing;
  final bool feather;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    Widget wrap(int i, Widget child) =>
        feather ? BrockmannFeather(index: i, child: child) : child;
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: BrockmannText(title, role: BrockmannType.heading),
              ),
              if (description != null) ...[
                const SizedBox(height: BrockmannSpace.xs),
                BrockmannText(description!, color: t.secondary),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: BrockmannSpace.m),
          trailing!,
        ],
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: spacing,
      children: [
        wrap(0, header),
        for (var i = 0; i < children.length; i++) wrap(i + 1, children[i]),
      ],
    );
  }
}

/// A large typographic page title. The size steps down on narrow screens so
/// it never competes with the content for space.
class BrockmannPageHeader extends StatelessWidget {
  const BrockmannPageHeader({
    super.key,
    required this.title,
    this.overline,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });
  final String title;
  final String? overline, subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return BrockmannResponsive(
      builder: (context, layout) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onBack != null) ...[
            Transform.translate(
              offset: const Offset(-12, 0),
              child: BrockmannIconButton(
                icon: BrockmannIcon.arrowLeft,
                label: 'Back',
                onPressed: onBack,
              ),
            ),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null) ...[
                  BrockmannText(
                    overline!.toUpperCase(),
                    role: BrockmannType.label,
                    color: t.secondary,
                  ),
                  const SizedBox(height: BrockmannSpace.xs),
                ],
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: BrockmannType.title
                        .style(color: t.foreground)
                        .copyWith(
                          fontSize: layout.value(compact: 32, medium: 40),
                          height: layout.value(compact: 36 / 32, medium: 1.1),
                        ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: BrockmannSpace.xs),
                  BrockmannText(subtitle!, color: t.secondary),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ),
    );
  }
}

/// A group of buttons that wraps instead of overflowing. Place the primary
/// action first; set [alignment] to [WrapAlignment.end] for dialogs.
class BrockmannButtonBar extends StatelessWidget {
  const BrockmannButtonBar({
    super.key,
    required this.children,
    this.alignment = WrapAlignment.start,
    this.spacing = BrockmannSpace.m,
  });
  final List<Widget> children;
  final WrapAlignment alignment;
  final double spacing;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignment,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: spacing,
    runSpacing: BrockmannSpace.s,
    children: children,
  );
}

/// A label above a value. Values use tabular mono figures so changing
/// numbers do not shift the layout.
class BrockmannStat extends StatelessWidget {
  const BrockmannStat({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.large = false,
    this.emphasis = false,
  });
  final String label, value;
  final String? caption;
  final bool large, emphasis;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrockmannText(label, role: BrockmannType.label, color: t.secondary),
          const SizedBox(height: BrockmannSpace.xxs),
          BrockmannText(
            value,
            role: large ? BrockmannType.monoLarge : BrockmannType.monoValue,
            color: emphasis ? t.accentText : t.foreground,
          ),
          if (caption != null) ...[
            const SizedBox(height: BrockmannSpace.xxs),
            BrockmannText(
              caption!,
              role: BrockmannType.caption,
              color: t.secondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// Aligned label/value rows, e.g. details or properties. Collapses to
/// stacked pairs when the width is too narrow for two columns.
class BrockmannPropertyList extends StatelessWidget {
  const BrockmannPropertyList({
    super.key,
    required this.entries,
    this.labelWidth = 160,
  });
  final Map<String, String> entries;
  final double labelWidth;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return LayoutBuilder(
      builder: (context, c) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final side = c.maxWidth >= labelWidth * scale * 2.2;
        final rows = <Widget>[];
        for (final e in entries.entries) {
          final label = BrockmannText(
            e.key,
            role: BrockmannType.label,
            color: t.secondary,
          );
          final value = BrockmannText(e.value);
          rows.add(
            MergeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: BrockmannSpace.s),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.line)),
                ),
                child: side
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          SizedBox(width: labelWidth * scale, child: label),
                          Expanded(child: value),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label,
                          const SizedBox(height: BrockmannSpace.xxs),
                          value,
                        ],
                      ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

/// A static placeholder block for content that is still loading. It never
/// animates: indeterminate motion belongs to [BrockmannProgress].
class BrockmannPlaceholder extends StatelessWidget {
  const BrockmannPlaceholder({
    super.key,
    this.width,
    this.height = 16,
    this.lines = 1,
  });
  final double? width;
  final double height;
  final int lines;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Semantics(
      label: 'Loading',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: BrockmannSpace.xs,
        children: [
          for (var i = 0; i < lines; i++)
            width != null
                ? SizedBox(
                    width: width,
                    height: height,
                    child: ColoredBox(color: t.surface),
                  )
                : FractionallySizedBox(
                    widthFactor: i == lines - 1 && lines > 1 ? .6 : 1,
                    child: SizedBox(
                      height: height,
                      child: ColoredBox(color: t.surface),
                    ),
                  ),
        ],
      ),
    );
  }
}

/// Vertical typographic navigation for wide layouts, the companion of
/// [BrockmannPivot]. The selected destination takes the accent and an inset
/// marker.
class BrockmannNavigationList extends StatelessWidget {
  const BrockmannNavigationList({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.header,
  });
  final List<String> options;
  final int selected;
  final ValueChanged<int>? onChanged;
  final Widget? header;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: BrockmannSpace.l),
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: header,
          ),
        for (var i = 0; i < options.length; i++)
          BrockmannPressable(
            label: options[i],
            selected: i == selected,
            onPressed: onChanged == null ? null : () => onChanged!(i),
            builder: (c, p) => BrockmannMotion(
              value: i == selected ? 1 : 0,
              milliseconds: 180,
              builder: (c, v) {
                final s = v.clamp(0.0, 1.0);
                return Container(
                  color: p ? t.surface : null,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 4,
                        height: 28 * s,
                        child: ColoredBox(color: t.accent),
                      ),
                      SizedBox(width: 12 * s),
                      Expanded(
                        child: BrockmannText(
                          options[i],
                          role: BrockmannType.heading,
                          weight: 300 + 100 * s,
                          color: Color.lerp(t.secondary, t.foreground, s),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// An adaptive application frame. On phones the destinations form a
/// typographic pivot above the body; from [breakpoint] on they become a
/// vertical [BrockmannNavigationList] beside it. The body is not rebuilt
/// with a new identity when the layout changes.
class BrockmannAdaptiveScaffold extends StatefulWidget {
  const BrockmannAdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onChanged,
    required this.body,
    this.title,
    this.actions = const [],
    this.breakpoint = 840,
    this.navigationWidth = 280,
  });
  final List<String> destinations;
  final int selected;
  final ValueChanged<int> onChanged;
  final Widget body;
  final String? title;
  final List<Widget> actions;
  final double breakpoint, navigationWidth;
  @override
  State<BrockmannAdaptiveScaffold> createState() =>
      _BrockmannAdaptiveScaffoldState();
}

class _BrockmannAdaptiveScaffoldState extends State<BrockmannAdaptiveScaffold> {
  final _bodyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final wide = MediaQuery.sizeOf(context).width >= widget.breakpoint;
    final titleRow = widget.title == null && widget.actions.isEmpty
        ? null
        : Row(
            children: [
              Expanded(
                child: widget.title == null
                    ? const SizedBox()
                    : BrockmannText(
                        widget.title!.toUpperCase(),
                        role: BrockmannType.label,
                        color: t.secondary,
                      ),
              ),
              ...widget.actions,
            ],
          );
    final keyedBody = KeyedSubtree(key: _bodyKey, child: widget.body);
    return Scaffold(
      backgroundColor: t.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: widget.navigationWidth,
                    child: BrockmannNavigationList(
                      options: widget.destinations,
                      selected: widget.selected,
                      onChanged: widget.onChanged,
                      header: titleRow,
                    ),
                  ),
                  const BrockmannDivider(axis: Axis.vertical),
                  Expanded(child: keyedBody),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (titleRow != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                      child: titleRow,
                    ),
                  const SizedBox(height: 12),
                  BrockmannPivot(
                    options: widget.destinations,
                    selected: widget.selected,
                    onChanged: widget.onChanged,
                  ),
                  Expanded(child: keyedBody),
                ],
              ),
      ),
    );
  }
}

/// List/detail. Side by side from [breakpoint]; on narrow screens shows the
/// detail only while [showDetail] is true, and Android Back calls
/// [onCloseDetail] to return to the list.
class BrockmannSplitView extends StatelessWidget {
  const BrockmannSplitView({
    super.key,
    required this.list,
    required this.detail,
    required this.showDetail,
    this.onCloseDetail,
    this.breakpoint = 720,
    this.listWidth = 360,
    this.placeholder,
  });
  final Widget list, detail;
  final Widget? placeholder;
  final bool showDetail;
  final VoidCallback? onCloseDetail;
  final double breakpoint, listWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth >= breakpoint) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: math.min(listWidth, c.maxWidth * .45), child: list),
            const BrockmannDivider(axis: Axis.vertical),
            Expanded(
              child: showDetail ? detail : (placeholder ?? const SizedBox()),
            ),
          ],
        );
      }
      final t = context.brockmann;
      return PopScope(
        canPop: !showDetail,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && showDetail) onCloseDetail?.call();
        },
        child: AnimatedSwitcher(
          duration: t.duration(context, 200),
          switchInCurve: brockmannOutExpo,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: t.motionReduced(context)
                ? child
                : SlideTransition(
                    position: Tween(
                      begin: const Offset(.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
          ),
          child: KeyedSubtree(
            key: ValueKey(showDetail),
            child: showDetail ? detail : list,
          ),
        ),
      );
    },
  );
}
