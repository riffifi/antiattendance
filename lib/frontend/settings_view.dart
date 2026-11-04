import 'package:flutter/material.dart';

import '../campus_design.dart';
import '../l10n.dart';
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
        if (embedded)
          CampusHeader(title: tr(context, 'Параметры', 'Preferences')),
        for (final section in sections) ...[
          AaSectionHeading(title: section.title),
          ...section.children,
          const SizedBox(height: 16),
        ],
      ],
    ),
  );
}
