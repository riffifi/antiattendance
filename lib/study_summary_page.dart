import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_theme.dart';
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
  Widget build(BuildContext context) => Scaffold(
    appBar: CampusAppBar(
      title: Text(tr(context, 'Итоги учебного дня', 'Study day summary')),
    ),
    body: CampusPageBody(
      child: _loading
          ? const Center(child: CampusProgress.compact())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Text(
                  tr(
                    context,
                    'Это подтверждения, записанные этим приложением.',
                    'These are confirmations recorded by this app.',
                  ),
                  style: TextStyle(color: context.palette.muted),
                ),
                const SizedBox(height: 16),
                if (_summary == null)
                  Text(
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
                  Text(
                    '${_summary!['id']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final person in _summary!['people'] as List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: CampusPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${person['name']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${person['counts']}',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    fontFamily: 'GeistMono',
                                    color: context.palette.muted,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            for (final line in person['lines'] as List)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('$line'),
                              ),
                            if (person['sessionExpired'] == true ||
                                person['sessionExpiresAt'] is int &&
                                    (person['sessionExpiresAt'] as int) <=
                                        (_summary!['at'] as int))
                              Text(
                                tr(
                                  context,
                                  'Нужно войти снова',
                                  'Sign-in needed',
                                ),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
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
