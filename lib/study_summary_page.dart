import 'dart:convert';

import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
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
      if (mounted) {
        setState(
          () => _summary = raw == null
              ? null
              : jsonDecode(raw) as Map<String, dynamic>,
        );
      }
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
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              children: [
                BrockmannText(
                  tr(
                    context,
                    'Это подтверждения, записанные этим приложением.',
                    'These are confirmations recorded by this app.',
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
