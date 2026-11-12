import 'dart:convert';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';
import 'study_summary.dart';

class StudySummaryPage extends StatefulWidget {
  const StudySummaryPage({super.key});
  @override
  State<StudySummaryPage> createState() => _StudySummaryPageState();
}

class _StudySummaryPageState extends State<StudySummaryPage> {
  Map<String, dynamic>? _summary;
  bool _loading = true;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final raw = await studySummaryChannel.invokeMethod<String>('last');
      final parsed = raw == null ? null : jsonDecode(raw);
      if (parsed != null) {
        if (parsed is! Map<String, dynamic> ||
            parsed['people'] is! List ||
            parsed['at'] is! int ||
            parsed['id'] is! String ||
            (parsed['people'] as List).any(
              (person) => person is! Map || person['lines'] is! List,
            )) {
          throw const FormatException('Invalid saved summary');
        }
        if (parsed['updatedAt'] is int) {
          // Validate before rendering; platform timestamps may be corrupt.
          DateTime.fromMillisecondsSinceEpoch(parsed['updatedAt'] as int);
        }
      }
      if (mounted) setState(() => _summary = parsed as Map<String, dynamic>?);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(
      title: Text(tr(context, 'Итоги учебного дня', 'Study day summary')),
    ),
    body: CampusPageBody(
      child: _loading
          ? const Center(child: CampusProgress.compact())
          : ListView(
              padding: AaPageLayout.insets(context),
              children: [
                BrockmannText(
                  tr(
                    context,
                    'Сохранённые результаты AA и Пульса. Отсутствие результата не означает пропуск занятия.',
                    'Saved results from AA and Pulse. Missing results are not absences.',
                  ),
                  role: BrockmannType.caption,
                  color: context.brockmann.secondary,
                ),
                const SizedBox(height: 16),
                if (_summary == null)
                  BrockmannText(
                    _failed
                        ? tr(
                            context,
                            'Не удалось загрузить итоги.',
                            'Could not load the summary.',
                          )
                        : tr(
                            context,
                            'Итоги появятся после последнего занятия.',
                            'The summary appears after the last class.',
                          ),
                  ),
                if (_summary != null) ...[
                  BrockmannText(
                    '${_summary!['id']}',
                    role: BrockmannType.value,
                    weight: 400,
                  ),
                  if (_summary!['updatedAt'] is int) ...[
                    const SizedBox(height: 8),
                    BrockmannText(
                      trf(
                        context,
                        'Результаты сохранены: {time}',
                        'Results saved at {time}',
                        {
                          'time':
                              '${MaterialLocalizations.of(context).formatShortDate(DateTime.fromMillisecondsSinceEpoch(_summary!['updatedAt'] as int))} ${TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(_summary!['updatedAt'] as int)).format(context)}',
                        },
                      ),
                      role: BrockmannType.caption,
                      color: context.brockmann.secondary,
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (final person in _summary!['people'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BrockmannText(
                            '${person['name']}',
                            role: BrockmannType.value,
                            weight: 400,
                          ),
                          const SizedBox(height: 4),
                          BrockmannText(
                            '${person['counts']}',
                            role: BrockmannType.monoValue,
                            color: context.brockmann.secondary,
                          ),
                          const SizedBox(height: 8),
                          for (final line in person['lines'] as List)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: BrockmannText('$line'),
                            ),
                          if (person['sessionExpired'] == true ||
                              person['sessionExpiresAt'] is int &&
                                  (person['sessionExpiresAt'] as int) <=
                                      (_summary!['at'] as int))
                            BrockmannText(
                              tr(
                                context,
                                'Нужно войти снова',
                                'Sign-in needed',
                              ),
                              color: context.brockmann.danger,
                            ),
                        ],
                      ),
                    ),
                ],
                if (_failed)
                  CampusButton.text(
                    onPressed: _load,
                    child: Text(tr(context, 'Повторить', 'Retry')),
                  ),
              ],
            ),
    ),
  );
}
