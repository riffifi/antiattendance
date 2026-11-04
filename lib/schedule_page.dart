import 'package:brockmann/brockmann.dart';

import 'campus_maps_page.dart';
import 'frontend/schedule_calendar.dart';
import 'frontend/page_layout.dart';
import 'campus_design.dart';
import 'expressive.dart';

import 'dart:async';
import 'dart:io';

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
    this.active = true,
    this.initialDay,
    this.initialGroupId,
    this.onDayChanged,
    this.onGroupChanged,
  });

  final List<SavedAccount> accounts;
  final ScheduleApi api;
  final AttendanceLogStore log;
  final Future<void> Function(ScheduleLesson, List<SavedAccount>) onScanLesson;
  final Future<void> Function(ScheduleLesson, List<SavedAccount>) onPasteLesson;
  final bool active;
  final DateTime? initialDay;
  final int? initialGroupId;
  final ValueChanged<DateTime>? onDayChanged;
  final ValueChanged<int>? onGroupChanged;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  int? _groupId;
  late DateTime _day = widget.initialDay ?? _today();
  List<ScheduleLesson> _lessons = [];
  List<AttendanceMark> _marks = [];
  bool _loading = false;
  String? _error;
  int _generation = 0;
  Timer? _clock;

  static DateTime _moscowNow() {
    final moscow = DateTime.now().toUtc().add(const Duration(hours: 3));
    return DateTime.utc(
      moscow.year,
      moscow.month,
      moscow.day,
      moscow.hour,
      moscow.minute,
      moscow.second,
    );
  }

  static DateTime _today() {
    final now = _moscowNow();
    return DateTime.utc(now.year, now.month, now.day);
  }

  static DateTime _weekOf(DateTime day) => DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).subtract(Duration(days: day.weekday - 1));

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int? _firstGroup() {
    for (final account in widget.accounts) {
      if (account.groupId != null) return account.groupId;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final ids = widget.accounts.map((account) => account.groupId).toSet();
    _groupId =
        widget.initialGroupId != null && ids.contains(widget.initialGroupId)
        ? widget.initialGroupId
        : _firstGroup();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.active) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.accounts.map((account) => account.groupId).toSet();
    if (_groupId == null || !ids.contains(_groupId)) {
      _groupId = _firstGroup();
      _refresh();
    } else if (widget.active && !oldWidget.active) {
      _reloadMarks();
    }
  }

  Future<void> _reloadMarks() async {
    final generation = _generation;
    try {
      final marks = await widget.log.load();
      if (mounted && generation == _generation) {
        setState(() => _marks = marks);
      }
    } catch (_) {
      // Keep the last known confirmations; pull-to-refresh can retry.
    }
  }

  Future<void> _refresh({bool force = false}) async {
    final generation = ++_generation;
    final groupId = _groupId;
    setState(() {
      _loading = true;
      _error = null;
      if (_lessons.any((lesson) => lesson.groupId != groupId)) {
        _lessons = [];
        _marks = [];
      }
    });
    try {
      final marks = await widget.log.load();
      final lessons = groupId == null
          ? <ScheduleLesson>[]
          : await widget.api.lessonsForWeek(
              groupId,
              _weekOf(_day),
              refresh: force,
            );
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

  void _selectDay(DateTime next) {
    final previousWeek = _weekOf(_day);
    setState(() => _day = next);
    widget.onDayChanged?.call(next);
    if (!_sameDay(previousWeek, _weekOf(next))) _refresh();
  }

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  List<AttendanceMark> _confirmed(ScheduleLesson lesson) =>
      _marks.where((mark) => mark.lessonKey == lesson.key).toList();

  Future<void> _openLesson(
    ScheduleLesson lesson,
    List<SavedAccount> groupAccounts,
  ) async {
    final confirmed = _confirmed(lesson);
    final action = await showExpressiveSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_date(lesson.start)}  ${_time(lesson.start)}–${_time(lesson.end)}',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lesson.subject,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
                  ),
                  if (lesson.type.isNotEmpty ||
                      lesson.location.isNotEmpty ||
                      lesson.teachers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      [
                        lesson.type,
                        lesson.location,
                        lesson.teachers,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      style: TextStyle(
                        color: context.palette.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (lesson.location.isNotEmpty)
                    CampusButton.action(
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => CampusMapsPage(
                            room: lesson.location,
                            lessons: [lesson],
                          ),
                        ),
                      ),
                      label: Text(tr(context, 'Найти аудиторию', 'Find room')),
                    ),
                  const SizedBox(height: 22),
                  Text(
                    tr(context, 'Подтверждённые Пульсом', 'Confirmed by Pulse'),
                    style: TextStyle(fontWeight: FontWeight.w400),
                  ),
                  const SizedBox(height: 8),
                  if (confirmed.isEmpty)
                    Text(
                      tr(context, 'Пока нет отметок', 'Nobody yet'),
                      style: TextStyle(color: context.palette.muted),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final mark in confirmed)
                          BrockmannChip(
                            label: mark.accountLabel,
                            selected: true,
                          ),
                      ],
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: CampusButton.action(
                      onPressed: groupAccounts.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              Platform.isAndroid || Platform.isIOS
                                  ? 'scan'
                                  : 'paste',
                            ),
                      label: Text(
                        Platform.isAndroid || Platform.isIOS
                            ? tr(context, 'Сканировать QR', 'Scan QR')
                            : tr(context, 'Вставить ссылку', 'Paste link'),
                      ),
                    ),
                  ),
                  if (Platform.isAndroid || Platform.isIOS)
                    SizedBox(
                      width: double.infinity,
                      child: CampusButton.action(
                        onPressed: groupAccounts.isEmpty
                            ? null
                            : () => Navigator.pop(context, 'paste'),
                        label: Text(
                          tr(context, 'Вставить ссылку', 'Paste link'),
                        ),
                        style: CampusButtonStyle.text,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'scan') {
      await widget.onScanLesson(lesson, groupAccounts);
    } else {
      await widget.onPasteLesson(lesson, groupAccounts);
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final groups = <int, String>{
      for (final account in widget.accounts)
        if (account.groupId != null)
          account.groupId!: account.groupName ?? '${account.groupId}',
    };
    final groupAccounts = widget.accounts
        .where((account) => account.groupId == _groupId)
        .toList();
    final today = _today();
    final now = _moscowNow();
    final dailyLessons = _lessons
        .where((lesson) => _sameDay(lesson.start, _day))
        .toList();
    final dayConfirmations = _marks.where((mark) {
      final local = mark.at.toUtc().add(const Duration(hours: 3));
      return mark.groupId == _groupId &&
          mark.lessonKey == null &&
          _sameDay(local, _day);
    }).toList();
    final dateText = MaterialLocalizations.of(context)
        .formatMediumDate(DateTime(_day.year, _day.month, _day.day));
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: ListView(
        key: const PageStorageKey('schedule-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AaPageLayout.insets(context),
        children: [
          CampusHeader(title: tr(context, 'Расписание', 'Schedule')),
          ScheduleCalendar(
            day: _day,
            today: today,
            groups: groups,
            groupId: _groupId,
            lessonDays: _lessons.map((l) => l.start).toSet(),
            loading: _loading,
            onDayChanged: (day) {
              if (mounted) _selectDay(day);
            },
            onGroupChanged: (id) {
              setState(() => _groupId = id);
              widget.onGroupChanged?.call(id);
              _refresh();
            },
            onRefresh: () => _refresh(force: true),
            onMaps: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => CampusMapsPage(lessons: dailyLessons),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (groups.isEmpty)
            AaEmptyState(
              title: tr(context, 'Выберите группу', 'Choose a group'),
              detail: tr(
                context,
                'Выберите группу в меню действий аккаунта на экране посещаемости.',
                'Assign a group to an account using its actions menu on the attendance screen.',
              ),
            )
          else ...[
            if (dailyLessons.isNotEmpty || _loading || _error != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sameDay(_day, today)
                              ? tr(context, 'Сегодня', 'Today')
                              : dateText,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        if (!_loading && _error == null)
                          Text(
                            (_sameDay(_day, today) ? '$dateText · ' : '') +
                                classCountLabel(context, dailyLessons.length),
                            style: TextStyle(
                              color: context.palette.muted,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),
            if (_error != null && dailyLessons.isNotEmpty) ...[
              Text(_error!, style: TextStyle(color: context.palette.muted)),
              const SizedBox(height: 12),
            ],
            if (_loading && dailyLessons.isEmpty) ...[
              const SizedBox(height: 25),
              const Center(child: CampusProgress.compact()),
            ] else if (_error != null && dailyLessons.isEmpty) ...[
              _EmptyPanel(
                title: _error!,
                detail: tr(
                  context,
                  'Потяните вниз или нажмите «Обновить».',
                  'Pull down or tap refresh to retry.',
                ),
              ),
            ] else if (dailyLessons.isEmpty) ...[
              _EmptyPanel(
                title: tr(context, 'Свободный день', 'A free day'),
                detail: tr(
                  context,
                  'В этот день занятий нет.',
                  'No classes on this day.',
                ),
              ),
            ] else ...[
              for (var index = 0; index < dailyLessons.length; index++) ...[
                if (index > 0) const SizedBox(height: 10),
                BrockmannFeather(
                  index: index,
                  child: _LessonRow(
                    lesson: dailyLessons[index],
                    confirmed: _confirmed(dailyLessons[index]),
                    time: _time(dailyLessons[index].start),
                    endTime: _time(dailyLessons[index].end),
                    isCurrent:
                        _sameDay(_day, today) &&
                        !now.isBefore(dailyLessons[index].start) &&
                        now.isBefore(dailyLessons[index].end),
                    onTap: () =>
                        _openLesson(dailyLessons[index], groupAccounts),
                    onRoom: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => CampusMapsPage(
                          room: dailyLessons[index].location,
                          lessons: dailyLessons,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
            if (dayConfirmations.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                tr(context, 'Другие отметки', 'Other confirmations'),
                style: TextStyle(fontWeight: FontWeight.w400),
              ),
              const SizedBox(height: 7),
              Text(
                dayConfirmations
                    .map((mark) => mark.accountLabel)
                    .toSet()
                    .join(', '),
                style: TextStyle(color: context.palette.muted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({
    required this.lesson,
    required this.confirmed,
    required this.time,
    required this.endTime,
    required this.isCurrent,
    required this.onTap,
    required this.onRoom,
  });
  final ScheduleLesson lesson;
  final List<AttendanceMark> confirmed;
  final String time;
  final String endTime;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRoom;

  @override
  Widget build(BuildContext context) {
    final t = context.brockmann;
    return BrockmannPressable(
      label: '',
      excludeSemantics: false,
      onPressed: onTap,
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: pressed ? t.surface : null,
          border: Border(
            bottom: BorderSide(color: isCurrent ? t.accent : t.line),
          ),
        ),
        child: BrockmannColumns(
          breakpoint: MediaQuery.textScalerOf(context).scale(16) > 22
              ? 600
              : 300,
          flex: const [1, 4],
          spacing: 16,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrockmannText(
                  time,
                  role: BrockmannType.monoValue,
                  color: isCurrent ? t.accentText : t.foreground,
                ),
                BrockmannText(
                  endTime,
                  role: BrockmannType.caption,
                  color: t.secondary,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isCurrent) ...[
                  BrockmannBadge(
                    label: tr(context, '● Сейчас', '● Now'),
                    tone: BrockmannTone.accent,
                  ),
                  const SizedBox(height: 8),
                ],
                BrockmannText(lesson.subject, role: BrockmannType.heading),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (lesson.type.isNotEmpty)
                      BrockmannText(
                        lesson.type,
                        role: BrockmannType.caption,
                        color: t.secondary,
                      ),
                    if (lesson.location.isNotEmpty)
                      CampusButton.text(
                        onPressed: onRoom,
                        child: Text(lesson.location),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                BrockmannText(
                  confirmed.isEmpty
                      ? tr(context, 'Нет отметок', 'No confirmations')
                      : confirmed.map((mark) => mark.accountLabel).join(', '),
                  role: BrockmannType.caption,
                  color: confirmed.isEmpty ? t.secondary : t.accentText,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) =>
      AaEmptyState(title: title, detail: detail);
}
