import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import '../campus_design.dart';
import '../l10n.dart';

/// Describes the pass being presented; never owns or starts the NFC service.
class PassStatusPanel extends StatelessWidget {
  const PassStatusPanel({
    super.key,
    required this.running,
    required this.single,
    required this.hasPasses,
    required this.accountLabel,
    required this.selectedCount,
    required this.responded,
    required this.remainingSeconds,
    required this.presented,
    required this.total,
  });
  final bool running, single, hasPasses, responded;
  final String? accountLabel;
  final int selectedCount, remainingSeconds, presented, total;
  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    final title = running
        ? single
              ? tr(context, 'Пропуск активен', 'Pass is active')
              : tr(context, 'Очередь работает', 'Queue is running')
        : hasPasses
        ? tr(context, 'Готовы к проходу', 'Ready for the gate')
        : tr(context, 'Подключите первый пропуск', 'Enroll your first pass');
    final detail = running
        ? single
              ? tr(
                  context,
                  'Один пропуск активен до остановки или истечения токена.',
                  'This pass stays active until stopped or its token expires.',
                )
              : responded
              ? trf(
                  context,
                  'Следующий через {seconds} с',
                  'Next pass in {seconds}s',
                  {'seconds': remainingSeconds},
                )
              : tr(
                  context,
                  'Приложите телефон к турникету',
                  'Hold your phone against the gate',
                )
        : !hasPasses
        ? tr(
            context,
            'Подключите пропуска выбранных аккаунтов.',
            'Enroll passes for your selected accounts.',
          )
        : single
        ? tr(
            context,
            'Выберите один пропуск ниже и активируйте его.',
            'Choose one pass below and activate it.',
          )
        : tr(
            context,
            'Выберите людей ниже и запустите очередь.',
            'Choose people below, then start the queue.',
          );
    return Semantics(
      liveRegion: running,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: running ? t.foreground : t.line),
            bottom: BorderSide(color: t.line),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BrockmannText(
              title,
              role: BrockmannType.caption,
              color: t.secondary,
            ),
            if (hasPasses || running) ...[
              const SizedBox(height: 12),
              BrockmannText(
                running
                    ? accountLabel ?? '—'
                    : single
                    ? accountLabel ??
                          tr(context, 'Выберите пропуск', 'Choose a pass')
                    : selectedCount == 1
                    ? tr(context, 'Выбран 1 пропуск', '1 pass selected')
                    : trf(
                        context,
                        'Выбрано пропусков: {count}',
                        '{count} passes selected',
                        {'count': selectedCount},
                      ),
                role: BrockmannType.heading,
              ),
            ],
            const SizedBox(height: 12),
            BrockmannText(
              detail,
              role: BrockmannType.caption,
              color: t.secondary,
            ),
            if (running && !single) ...[
              const SizedBox(height: 16),
              CampusProgress.linear(
                value: total == 0 ? 0 : (presented / total).clamp(0, 1),
              ),
              const SizedBox(height: 8),
              BrockmannText(
                trf(
                  context,
                  'Предъявлено: {count} из {total}',
                  'Presented: {count} of {total}',
                  {'count': presented, 'total': total},
                ),
                role: BrockmannType.caption,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
