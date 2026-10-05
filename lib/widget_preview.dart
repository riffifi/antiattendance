import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'app_theme.dart';
import 'campus_design.dart';
import 'expressive.dart';
import 'l10n.dart';

Future<bool?> showWidgetPreview(BuildContext context, {required bool nfc}) =>
    showExpressiveSheet<bool>(
      context: context,
      compact: true,
      builder: (context) {
        var compact = false;
        return StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(context, 'Предпросмотр виджета', 'Widget preview'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                for (final small in [false, true])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: M3EListItem(
                      headline: small
                          ? tr(context, 'Компактный · 1×1', 'Compact · 1×1')
                          : tr(context, 'С подписью · 2×1', 'Labeled · 2×1'),
                      selected: compact == small,
                      onTap: () => setState(() => compact = small),
                      leading: M3ECheckbox(
                        value: compact == small,
                        onChanged: (_) => setState(() => compact = small),
                      ),
                      trailing: WidgetPreview(nfc: nfc, compact: small),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: CampusButton.filled(
                    onPressed: () => Navigator.pop(context, compact),
                    child: Text(tr(context, 'Добавить виджет', 'Add widget')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

class WidgetPreview extends StatelessWidget {
  const WidgetPreview({super.key, required this.nfc, required this.compact});
  final bool nfc;
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    width: compact ? 52 : 128,
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: context.palette.paper,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.palette.line),
    ),
    child: Row(
      mainAxisAlignment: compact
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        Icon(
          nfc ? Icons.nfc_rounded : Icons.qr_code_scanner_rounded,
          size: 26,
          color: context.palette.ink,
        ),
        if (!compact) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nfc
                  ? tr(context, 'Пропуска', 'Passes')
                  : tr(context, 'Отметить всех', 'Mark all'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    ),
  );
}
