import 'package:flutter/material.dart';

import 'theme.dart';
import 'foundation.dart';
import 'pickers.dart';
import 'controls.dart';
import 'feedback.dart';

/// Flat modal with wrapped, touch-sized text actions. Android back dismisses it.
Future<String?> showBrockmannDialog(
  BuildContext context, {
  required String title,
  required String message,
  List<String> actions = const ['close'],
}) async {
  final feedback = BrockmannFeedbackScope.of(context);
  feedback?.play(BrockmannSound.open);
  final result = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close $title',
    barrierColor: Colors.black.withValues(
      alpha: context.brockmann.light ? .4 : .6,
    ),
    transitionDuration: context.brockmann.duration(context, 160),
    pageBuilder: (c, _, _) => _FlatDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            namesRoute: true,
            child: BrockmannText(title, role: BrockmannType.heading),
          ),
          const SizedBox(height: 16),
          BrockmannText(message),
          const SizedBox(height: 24),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (var i = 0; i < actions.length; i++)
                BrockmannButton(
                  label: actions[i],
                  style: i == 0
                      ? BrockmannButtonStyle.primary
                      : BrockmannButtonStyle.text,
                  onPressed: () => Navigator.pop(c, actions[i]),
                ),
            ],
          ),
        ],
      ),
    ),
    transitionBuilder: (c, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );
  feedback?.play(BrockmannSound.close);
  return result;
}

/// Arbitrary form content in Brockmann's flat, keyboard-safe dialog band.
class BrockmannDialog extends StatelessWidget {
  const BrockmannDialog({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
    this.scrollable = true,
  });
  final Widget? title, content;
  final List<Widget> actions;
  final bool scrollable;
  @override
  Widget build(BuildContext context) => _FlatDialog(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          DefaultTextStyle(
            style: BrockmannType.heading.style(
              color: context.brockmann.foreground,
            ),
            child: title!,
          ),
        if (title != null && content != null) const SizedBox(height: 16),
        ?content,
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 16,
            runSpacing: 12,
            children: actions,
          ),
        ],
      ],
    ),
  );
}

class _FlatDialog extends StatelessWidget {
  const _FlatDialog({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: Material(
          color: t.surface,
          shape: Border.symmetric(
            horizontal: BorderSide(color: t.line, width: 0),
          ),
          child: SizedBox(
            width: double.infinity,
            child: SafeArea(
              top: false,
              bottom: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showBrockmannToast(BuildContext context, String message) {
  final t = context.brockmann;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: BrockmannText(message),
        backgroundColor: t.surface,
        elevation: 0,
        shape: Border(top: BorderSide(color: t.line)),
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(milliseconds: 2800),
      ),
    );
}

Future<String?> showBrockmannMenu(
  BuildContext context, {
  required String label,
  required List<String> actions,
}) async {
  BrockmannFeedbackScope.play(context, BrockmannSound.open);
  final result = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close $label',
    transitionDuration: context.brockmann.duration(context, 160),
    pageBuilder: (c, _, _) => _FlatDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrockmannText(
            label,
            role: BrockmannType.label,
            color: c.brockmann.secondary,
          ),
          const SizedBox(height: 12),
          for (final action in actions)
            BrockmannButton(
              label: action,
              style: BrockmannButtonStyle.text,
              onPressed: () => Navigator.pop(c, action),
            ),
        ],
      ),
    ),
    transitionBuilder: (c, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );
  if (context.mounted) {
    BrockmannFeedbackScope.play(context, BrockmannSound.close);
  }
  return result;
}

Future<String?> showBrockmannCommands(
  BuildContext context,
  List<String> commands,
) async {
  BrockmannFeedbackScope.play(context, BrockmannSound.open);
  final result = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close commands',
    transitionDuration: context.brockmann.duration(context, 160),
    pageBuilder: (c, _, _) => _CommandDialog(commands: commands),
    transitionBuilder: (c, a, _, child) =>
        FadeTransition(opacity: a, child: child),
  );
  if (context.mounted) {
    BrockmannFeedbackScope.play(context, BrockmannSound.close);
  }
  return result;
}

class _CommandDialog extends StatefulWidget {
  const _CommandDialog({required this.commands});
  final List<String> commands;
  @override
  State<_CommandDialog> createState() => _CommandDialogState();
}

class _CommandDialogState extends State<_CommandDialog> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.commands
        .where((c) => c.toLowerCase().contains(_query.text.toLowerCase()))
        .toList();
    return _FlatDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrockmannTextField(
            label: 'Find a command',
            controller: _query,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (matches.isEmpty) const BrockmannText('No matching commands'),
          for (final command in matches.take(12))
            BrockmannButton(
              label: command,
              style: BrockmannButtonStyle.text,
              onPressed: () => Navigator.pop(context, command),
            ),
        ],
      ),
    );
  }
}

/// One typed menu definition can be used by a context menu or action sheet.
@immutable
class BrockmannMenuEntry<T> {
  const BrockmannMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
    this.destructive = false,
    this.leading,
    this.trailing,
    this.secondary,
  });
  final T value;
  final String label;
  final BrockmannIcon? icon;
  final bool enabled, destructive;
  final Widget? leading, trailing;
  final String? secondary;
}

Future<T?> showBrockmannContextMenu<T>(
  BuildContext context, {
  required Offset position,
  required List<BrockmannMenuEntry<T>> entries,
  bool showIcons = true,
}) {
  return showBrockmannActionSheet<T>(
    context,
    title: 'actions',
    entries: entries,
    showIcons: showIcons,
  );
}

class BrockmannContextMenu<T> extends StatelessWidget {
  const BrockmannContextMenu({
    super.key,
    required this.entries,
    required this.onSelected,
    required this.child,
  });
  final List<BrockmannMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    Future<void> open(Offset p) async {
      final result = await showBrockmannContextMenu(
        context,
        position: p,
        entries: entries,
      );
      if (result != null && context.mounted) onSelected(result);
    }

    return GestureDetector(
      onLongPressStart: (d) => open(d.globalPosition),
      onSecondaryTapDown: (d) => open(d.globalPosition),
      child: child,
    );
  }
}

/// A typographic command band: a quiet context label above generous actions.
Future<T?> showBrockmannActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<BrockmannMenuEntry<T>> entries,
  bool showIcons = true,
}) {
  final t = context.brockmann;
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    sheetAnimationStyle: AnimationStyle(
      duration: t.duration(context, 220),
      reverseDuration: t.duration(context, 200),
    ),
    backgroundColor: t.surface,
    elevation: 0,
    shape: Border(top: BorderSide(color: t.line)),
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .8),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: BrockmannText(
                      title,
                      role: BrockmannType.label,
                      color: t.secondary,
                    ),
                  ),
                  for (final entry in entries)
                    BrockmannPressable(
                      label: entry.label,
                      onPressed: entry.enabled
                          ? () => Navigator.pop(c, entry.value)
                          : null,
                      builder: (c, pressed) => AnimatedContainer(
                        duration: t.duration(c, pressed ? 60 : 160),
                        constraints: const BoxConstraints(minHeight: 64),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        color: pressed
                            ? t.line.withValues(alpha: .3)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            if (entry.leading != null) ...[
                              entry.leading!,
                              const SizedBox(width: 16),
                            ],
                            if (entry.icon != null && showIcons) ...[
                              BrockmannGlyph(
                                entry.icon!,
                                color: !entry.enabled
                                    ? t.disabled
                                    : entry.destructive
                                    ? t.danger
                                    : t.secondary,
                              ),
                              const SizedBox(width: 16),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  BrockmannText(
                                    entry.label,
                                    role: BrockmannType.heading,
                                    weight: 300,
                                    color: !entry.enabled
                                        ? t.disabled
                                        : entry.destructive
                                        ? t.danger
                                        : t.foreground,
                                  ),
                                  if (entry.secondary != null) ...[
                                    const SizedBox(height: 4),
                                    BrockmannText(
                                      entry.secondary!,
                                      role: BrockmannType.caption,
                                      color: t.secondary,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (entry.trailing != null) ...[
                              const SizedBox(width: 12),
                              entry.trailing!,
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<DateTime?> showBrockmannDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? title,
  String? confirmLabel,
  String? cancelLabel,
}) {
  final first = DateUtils.dateOnly(firstDate),
      last = DateUtils.dateOnly(lastDate);
  var draft = DateUtils.dateOnly(initialDate);
  assert(
    !last.isBefore(first) && !draft.isBefore(first) && !draft.isAfter(last),
  );
  return _showTypedPicker<DateTime>(
    context,
    title ?? 'choose date',
    (c, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrockmannText(title ?? 'choose date', role: BrockmannType.heading),
        const SizedBox(height: 16),
        BrockmannCalendar(
          value: draft,
          firstDate: first,
          lastDate: last,
          onChanged: (v) => set(() => draft = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            BrockmannButton(
              label: confirmLabel ?? 'use date',
              style: BrockmannButtonStyle.secondary,
              onPressed: () => Navigator.pop(c, draft),
            ),
            BrockmannButton(
              label: cancelLabel ?? 'cancel',
              style: BrockmannButtonStyle.text,
              onPressed: () => Navigator.pop(c),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<TimeOfDay?> showBrockmannTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  var draft = initialTime;
  return _showTypedPicker<TimeOfDay>(
    context,
    'choose time',
    (c, set) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrockmannText('choose time', role: BrockmannType.heading),
        const SizedBox(height: 16),
        BrockmannTimePicker(
          value: draft,
          onChanged: (v) => set(() => draft = v),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            BrockmannButton(
              label: 'use time',
              style: BrockmannButtonStyle.secondary,
              onPressed: () => Navigator.pop(c, draft),
            ),
            BrockmannButton(
              label: 'cancel',
              style: BrockmannButtonStyle.text,
              onPressed: () => Navigator.pop(c),
            ),
          ],
        ),
      ],
    ),
  );
}

Future<T?> _showTypedPicker<T>(
  BuildContext context,
  String title,
  Widget Function(BuildContext, StateSetter) content,
) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close $title',
  barrierColor: Colors.black.withValues(
    alpha: context.brockmann.light ? .4 : .6,
  ),
  transitionDuration: context.brockmann.duration(context, 220),
  pageBuilder: (c, _, _) =>
      StatefulBuilder(builder: (c, set) => _FlatDialog(child: content(c, set))),
  transitionBuilder: (c, a, _, child) =>
      FadeTransition(opacity: a, child: child),
);

/// A discoverable overflow affordance; both orientations use the same typed
/// context-menu actions and retain accessible labels and a 48 dp target.
class BrockmannOverflowMenu<T> extends StatelessWidget {
  const BrockmannOverflowMenu({
    super.key,
    required this.entries,
    required this.onSelected,
    this.label = 'More actions',
    this.vertical = false,
    this.showIcons = true,
  });
  final List<BrockmannMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final String label;
  final bool vertical;
  final bool showIcons;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (buttonContext) => BrockmannIconButton(
      icon: vertical
          ? BrockmannIcon.dotsThreeVertical
          : BrockmannIcon.dotsThree,
      label: label,
      onPressed: () async {
        final box = buttonContext.findRenderObject() as RenderBox;
        final result = await showBrockmannContextMenu<T>(
          context,
          position: box.localToGlobal(Offset(0, box.size.height)),
          entries: entries,
          showIcons: showIcons,
        );
        if (context.mounted && result != null) onSelected(result);
      },
    ),
  );
}
