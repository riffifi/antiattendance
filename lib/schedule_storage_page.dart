import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';

import 'campus_design.dart';
import 'frontend/page_layout.dart';
import 'l10n.dart';
import 'server_schedule_cache.dart';

class ScheduleStoragePage extends StatefulWidget {
  const ScheduleStoragePage({super.key, this.cache});
  final ServerScheduleCache? cache;
  @override
  State<ScheduleStoragePage> createState() => _ScheduleStoragePageState();
}

class _ScheduleStoragePageState extends State<ScheduleStoragePage> {
  late final _cache = widget.cache ?? ServerScheduleCache();
  bool _busy = false;
  int? _weeks;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool clear = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (clear) await _cache.clearAll();
      final count = await _cache.countWeeks();
      if (mounted) setState(() => _weeks = count);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            context,
            'Не удалось обновить сохранённые расписания. Повторите попытку.',
            'Could not update saved schedules. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CampusScaffold(
    appBar: CampusAppBar(
      title: Text(tr(context, 'Без сети', 'Offline schedules')),
    ),
    body: ListView(
      padding: AaPageLayout.insets(context),
      children: [
        BrockmannText(
          tr(
            context,
            'Сохранённые недели доступны без сети до 14 дней. Откройте расписание с доступом к сети, чтобы обновить его.',
            'Saved weeks can be used offline for up to 14 days. Open the schedule online to refresh it.',
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 20,
          child: _busy ? const CampusProgress.compact() : null,
        ),
        if (_weeks != null)
          Semantics(
            liveRegion: true,
            child: CampusValueTransition(
              trf(
                context,
                'Сохранено недель: {count}',
                'Saved weeks: {count}',
                {'count': _weeks!},
              ),
              role: BrockmannType.heading,
            ),
          ),
        const SizedBox(height: 24),
        if (_error != null) ...[
          BrockmannText(_error!, color: context.brockmann.danger),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: CampusButton.text(
              onPressed: _busy ? null : () => _load(),
              child: Text(tr(context, 'Повторить', 'Retry')),
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: CampusButton.filled(
            onPressed: _busy ? null : () => _load(clear: true),
            child: Text(
              tr(context, 'Очистить расписания', 'Clear saved schedules'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        BrockmannText(
          tr(
            context,
            'Аккаунты, пропуска и настройки останутся. Сохранённые расписания всех групп будут удалены только с этого устройства.',
            'Accounts, passes and settings stay in place. Saved schedules for all groups are removed only from this device.',
          ),
          role: BrockmannType.caption,
          color: context.brockmann.secondary,
        ),
      ],
    ),
  );
}
