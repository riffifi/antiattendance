import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import '../app_haptics.dart';
import '../icons/campus_icon.dart';

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

/// WP8's command vocabulary: circled glyphs, quiet labels, a fixed bottom band.
class CampusCommandBar extends StatelessWidget {
  const CampusCommandBar({super.key, required this.commands, this.overflow})
    : assert(commands.length <= 4);
  final List<CampusCommand> commands;
  final Widget? overflow;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return BrockmannInteractionRegion(
      child: ColoredBox(
        color: t.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final command in commands)
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 136),
                      child: Tooltip(
                        message: command.tooltip ?? command.label,
                        excludeFromSemantics: true,
                        child: BrockmannPressable(
                          label: command.tooltip ?? command.label,
                          onPressed: command.onPressed == null
                              ? null
                              : () {
                                  AppHaptics.action(primary: false);
                                  command.onPressed!();
                                },
                          builder: (context, pressed) {
                            final ink = command.onPressed == null
                                ? t.disabled
                                : t.foreground;
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: ink,
                                        width: 1.5,
                                      ),
                                      color: pressed ? ink : null,
                                    ),
                                    child: CampusIcon(
                                      command.icon,
                                      size: 20,
                                      color: pressed ? t.background : ink,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    command.label,
                                    textAlign: TextAlign.center,
                                    style: BrockmannType.caption.style(
                                      color: ink,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ?overflow,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
