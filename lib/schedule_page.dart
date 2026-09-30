import 'package:flutter/material.dart';

import 'accounts.dart';
import 'app_theme.dart';
import 'attendance_log.dart';
import 'l10n.dart';
import 'schedule_api.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.accounts,
    required this.api,
    required this.log,
    required this.onScanLesson,
    required this.onPasteLesson,
  });
  final List<SavedAccount> accounts;
  final ScheduleApi api;
  final AttendanceLogStore log;
  final Future<void> Function(ScheduleLesson, List<SavedAccount>) onScanLesson;
  final Future<void> Function(ScheduleLesson, List<SavedAccount>) onPasteLesson;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  int? _groupId;
  late DateTime _week = _monday(DateTime.now());
  List<ScheduleLesson> _lessons = [];
  List<AttendanceMark> _marks = [];
  bool _loading = false;
  String? _error;
  int _generation = 0;

  static DateTime _monday(DateTime day) => DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).subtract(Duration(days: day.weekday - 1));

  int? _firstGroup() {
    for (final account in widget.accounts) {
      if (account.groupId != null) return account.groupId;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _groupId = _firstGroup();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.accounts.map((a) => a.groupId).toSet();
    if (_groupId == null || !ids.contains(_groupId)) {
      _groupId = _firstGroup();
      _refresh();
    }
  }

  Future<void> _refresh({bool force = false}) async {
    final generation = ++_generation;
    final groupId = _groupId;
    setState(() {
      _loading = true;
      _error = null;
      _lessons = [];
      _marks = [];
    });
    try {
      final marks = await widget.log.load();
      final lessons = groupId == null
          ? <ScheduleLesson>[]
          : await widget.api.lessonsForWeek(groupId, _week, refresh: force);
      if (mounted && generation == _generation) {
        setState(() {
          _marks = marks;
          _lessons = lessons;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = tr(
            context,
            'Не удалось загрузить расписание.',
            'Could not load the schedule.',
          ),
        );
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  String _date(DateTime day) =>
      '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}';
  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final groups = <int, String>{
      for (final account in widget.accounts)
        if (account.groupId != null && account.groupName != null)
          account.groupId!: account.groupName!,
    };
    final groupAccounts = widget.accounts
        .where((a) => a.groupId == _groupId)
        .toList();
    final unattached = _marks
        .where(
          (mark) =>
              mark.groupId == _groupId &&
              mark.lessonKey == null &&
              !mark.at.toUtc().add(const Duration(hours: 3)).isBefore(_week) &&
              mark.at
                  .toUtc()
                  .add(const Duration(hours: 3))
                  .isBefore(_week.add(const Duration(days: 7))),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Text(
            tr(context, 'Расписание', 'Schedule'),
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              context,
              'Отметки здесь сохранены на этом устройстве после ответа Пульса.',
              'Marks here are saved on this device after Pulse confirms them.',
            ),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (groups.isEmpty)
            Text(
              tr(
                context,
                'Назначьте группу аккаунту через меню ⋮ на вкладке посещаемости.',
                'Assign a group to an account using the ⋮ menu on the attendance tab.',
              ),
            )
          else ...[
            DropdownButtonFormField<int>(
              initialValue: groups.containsKey(_groupId) ? _groupId : null,
              decoration: InputDecoration(
                labelText: tr(context, 'Группа', 'Group'),
              ),
              items: [
                for (final entry in groups.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (id) {
                setState(() => _groupId = id);
                _refresh();
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(
                      () => _week = _week.subtract(const Duration(days: 7)),
                    );
                    _refresh();
                  },
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_date(_week)} – ${_date(_week.add(const Duration(days: 6)))}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() => _week = _week.add(const Duration(days: 7)));
                    _refresh();
                  },
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                IconButton(
                  onPressed: () => _refresh(force: true),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: tr(context, 'Обновить', 'Refresh'),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            if (!_loading && _error == null && _lessons.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  tr(
                    context,
                    'На этой неделе занятий нет.',
                    'No classes this week.',
                  ),
                ),
              ),
            for (final lesson in _lessons) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_date(lesson.start)}  ${_time(lesson.start)}–${_time(lesson.end)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      lesson.subject,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (lesson.type.isNotEmpty || lesson.location.isNotEmpty)
                      Text(
                        [
                          lesson.type,
                          lesson.location,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    if (lesson.teachers.isNotEmpty)
                      Text(
                        lesson.teachers,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      tr(context, 'Подтверждены', 'Confirmed'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final confirmed = _marks
                            .where((mark) => mark.lessonKey == lesson.key)
                            .toList();
                        return Text(
                          confirmed.isEmpty
                              ? tr(context, 'Пока никого', 'Nobody yet')
                              : confirmed
                                    .map((mark) => mark.accountLabel)
                                    .join(', '),
                          style: TextStyle(
                            color: confirmed.isEmpty
                                ? AppColors.muted
                                : const Color(0xFF238664),
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: groupAccounts.isEmpty
                          ? null
                          : () async {
                              await widget.onScanLesson(lesson, groupAccounts);
                              if (mounted) _refresh();
                            },
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: Text(
                        tr(context, 'Отметить эту пару', 'Mark this class'),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: groupAccounts.isEmpty
                          ? null
                          : () async {
                              await widget.onPasteLesson(lesson, groupAccounts);
                              if (mounted) _refresh();
                            },
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(tr(context, 'Вставить ссылку', 'Paste link')),
                    ),
                  ],
                ),
              ),
            ],
            if (unattached.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                tr(
                  context,
                  'Другие подтверждения на этой неделе',
                  'Other confirmations this week',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                unattached.map((mark) => mark.accountLabel).toSet().join(', '),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
