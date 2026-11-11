import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import '../app_haptics.dart';
import '../icons/campus_icon.dart';
import '../l10n.dart';

@immutable
class CampusCommand {
  const CampusCommand({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
}

/// AA icons, localization and haptics on the shared phone application bar.
class CampusCommandBar extends StatelessWidget {
  const CampusCommandBar({
    super.key,
    required this.commands,
    this.active = true,
    this.onModeChanged,
  });
  final List<CampusCommand> commands;
  final bool active;
  final ValueChanged<BrockmannCommandBarMode>? onModeChanged;
  @override
  Widget build(BuildContext context) => BrockmannCommandBar(
    active: active,
    onModeChanged: onModeChanged,
    expandLabel: tr(context, 'Развернуть панель', 'Expand app bar'),
    collapseLabel: tr(context, 'Свернуть панель', 'Collapse app bar'),
    minimizeLabel: tr(context, 'Скрыть команды', 'Minimize app bar'),
    commands: [
      for (final command in commands)
        BrockmannCommand(
          icon: CampusIcon(command.icon, size: 20),
          label: command.label,
          tooltip: command.tooltip,
          onPressed: command.onPressed == null
              ? null
              : () {
                  AppHaptics.action(primary: false);
                  command.onPressed!();
                },
        ),
    ],
  );
}
