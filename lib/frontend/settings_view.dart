import 'package:flutter/material.dart';
import 'package:brockmann/brockmann.dart';

import '../campus_design.dart';
import 'page_layout.dart';

@immutable
class SettingsSection {
  const SettingsSection(this.title, this.children);
  final String title;
  final List<Widget> children;
}

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.embedded,
    required this.sections,
  });
  final bool embedded;
  final List<SettingsSection> sections;
  @override
  Widget build(BuildContext context) => CampusPageBody(
    child: ListView(
      padding: AaPageLayout.insets(context),
      children: [
        for (final (sectionIndex, section) in sections.indexed) ...[
          Padding(
            padding: EdgeInsets.only(
              top: sectionIndex == 0 ? 8 : 24,
              bottom: 8,
            ),
            child: Semantics(
              header: true,
              child: BrockmannText(
                section.title.toUpperCase(),
                role: BrockmannType.label,
                color: context.brockmann.secondary,
              ),
            ),
          ),
          for (final (index, child) in section.children.indexed)
            BrockmannFeather(index: index + 1, child: child),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );
}
