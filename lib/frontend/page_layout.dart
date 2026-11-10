import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

/// A single reading column and spacing rhythm for feature screens.
abstract final class AaPageLayout {
  static const maxWidth = 960.0;
  static double gutter(BuildContext context, {bool title = false}) {
    if (MediaQuery.sizeOf(context).width >= 600) return 40;
    // Windows Phone: titles align to 24, lists and other content to 12.
    return title ? 24 : 12;
  }

  static double titleNudge(BuildContext context) =>
      gutter(context, title: true) - gutter(context);

  static EdgeInsets insets(BuildContext context) => EdgeInsets.fromLTRB(
    gutter(context),
    12,
    gutter(context),
    MediaQuery.paddingOf(context).bottom + 32,
  );
}

class AaEmptyState extends StatelessWidget {
  const AaEmptyState({
    super.key,
    required this.title,
    required this.detail,
    this.action,
  });
  final String title, detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrockmannText(title, role: BrockmannType.heading),
        const SizedBox(height: 12),
        BrockmannText(detail, color: context.brockmann.secondary),
        if (action != null) ...[const SizedBox(height: 24), action!],
      ],
    ),
  );
}

/// Uses wrapping instead of squeezing actions at large system text sizes.
class AaSectionHeading extends StatelessWidget {
  const AaSectionHeading({super.key, required this.title, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Semantics(
          header: true,
          child: BrockmannText(
            title.toLowerCase(),
            role: BrockmannType.heading,
          ),
        ),
        ?action,
      ],
    ),
  );
}
