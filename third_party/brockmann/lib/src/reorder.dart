import 'package:flutter/semantics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'theme.dart';
import 'feedback.dart';
import 'interaction.dart';

/// Stable keyed children, flat drag proxy, automatic edge scroll and neighbour motion.
/// `newIndex` is already adjusted for removal (Flutter 3.47 onReorderItem API).
class BrockmannReorderableList extends StatelessWidget {
  const BrockmannReorderableList({
    super.key,
    required this.children,
    required this.onReorder,
    this.shrinkWrap = false,
    this.controller,
    this.padding = EdgeInsets.zero,
    this.axis = Axis.vertical,
    this.physics,
    this.header,
    this.spacing = 0,
  }) : assert(spacing >= 0);
  final List<Widget> children;
  final void Function(int oldIndex, int newIndex) onReorder;
  final bool shrinkWrap;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;
  final Axis axis;
  final ScrollPhysics? physics;
  final Widget? header;

  /// Space between items; it is never part of the drag outline.
  final double spacing;
  @override
  Widget build(BuildContext context) {
    assert(
      children.every((c) => c.key != null),
      'Reorderable children need stable identity keys.',
    );
    final t = context.brockmann;
    void move(int a, int b) {
      if (a == b) return;
      onReorder(a, b);
    }

    return BrockmannInteractionRegion(
      child: ReorderableListView.builder(
        header: header,
        buildDefaultDragHandles: false,
        itemCount: children.length,
        onReorderItem: move,
        onReorderStart: (_) =>
            BrockmannFeedbackScope.of(context)?.gesture(lifting: true),
        onReorderEnd: (_) =>
            BrockmannFeedbackScope.of(context)?.gesture(lifting: false),
        scrollController: controller,
        shrinkWrap: shrinkWrap,
        padding: padding.resolve(Directionality.of(context)),
        scrollDirection: axis,
        physics: physics ?? const ClampingScrollPhysics(),
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, _) => _ReorderDragScope(
            amount: Curves.easeOut.transform(animation.value),
            child: Theme(
              data: Theme.of(context).copyWith(
                extensions: [
                  ...Theme.of(context).extensions.values
                      .where((e) => e is! BrockmannThemeData),
                  t.copyWith(tilt: false),
                ],
              ),
              child: child,
            ),
          ),
        ),
        itemBuilder: (c, i) => Semantics(
          key: children[i].key,
          customSemanticsActions: {
            if (i > 0)
              const CustomSemanticsAction(label: 'Move earlier'): () {
                move(i, i - 1);
                BrockmannFeedbackScope.of(context)?.gesture(lifting: false);
              },
            if (i + 1 < children.length)
              const CustomSemanticsAction(label: 'Move later'): () {
                move(i, i + 1);
                BrockmannFeedbackScope.of(context)?.gesture(lifting: false);
              },
          },
          child: Padding(
            padding: axis == Axis.vertical
                ? EdgeInsets.only(bottom: i + 1 < children.length ? spacing : 0)
                : EdgeInsetsDirectional.only(
                    end: i + 1 < children.length ? spacing : 0,
                  ),
            child: _TouchReorderListener(index: i, child: children[i]),
          ),
        ),
      ),
    );
  }
}

/// Wrap the painted bounds of custom reorderable content, inside its margins.
/// BrockmannTile already includes this surface. Padding and gaps remain unmarked.
class BrockmannReorderableItem extends StatelessWidget {
  const BrockmannReorderableItem({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final amount =
        context
            .dependOnInheritedWidgetOfExactType<_ReorderDragScope>()
            ?.amount ??
        0;
    return DecoratedBox(
      key: amount > 0 ? const ValueKey('brockmann-reorder-outline') : null,
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: amount > 0
            ? Border.all(
                color: context.brockmann.accent.withValues(alpha: amount),
                width: 2,
              )
            : null,
      ),
      child: child,
    );
  }
}

class _ReorderDragScope extends InheritedWidget {
  const _ReorderDragScope({required this.amount, required super.child});
  final double amount;
  @override
  bool updateShouldNotify(_ReorderDragScope oldWidget) =>
      amount != oldWidget.amount;
}

class _TouchReorderListener extends ReorderableDragStartListener {
  const _TouchReorderListener({required super.index, required super.child});
  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(
        delay: const Duration(milliseconds: 250),
        debugOwner: this,
      );
}
