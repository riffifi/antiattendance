import 'campus_maps_page.dart';
import 'campus_design.dart';
import 'expressive.dart';

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

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
                          Chip(
                            label: Text(mark.accountLabel),
                            backgroundColor: context.palette.mint,
                            side: BorderSide.none,
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
        if (account.groupId != null && account.groupName != null)
          account.groupId!: account.groupName!,
    };
    final groupAccounts = widget.accounts
        .where((account) => account.groupId == _groupId)
        .toList();
    final week = _weekOf(_day);
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
    final dayNames = [
      tr(context, 'Пн', 'Mon'),
      tr(context, 'Вт', 'Tue'),
      tr(context, 'Ср', 'Wed'),
      tr(context, 'Чт', 'Thu'),
      tr(context, 'Пт', 'Fri'),
      tr(context, 'Сб', 'Sat'),
      tr(context, 'Вс', 'Sun'),
    ];
    final dateText = MaterialLocalizations.of(context)
        .formatMediumDate(DateTime(_day.year, _day.month, _day.day));
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: ListView(
        key: const PageStorageKey('schedule-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          MediaQuery.paddingOf(context).bottom + 32,
        ),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'Расписание', 'Schedule'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                children: [
                  CampusTextAction(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => CampusMapsPage(lessons: dailyLessons),
                      ),
                    ),
                    tooltip: tr(context, 'Карты кампусов', 'Campus maps'),
                    label: tr(context, 'карты', 'maps'),
                  ),
                  CampusTextAction(
                    onPressed: groups.isEmpty || _loading
                        ? null
                        : () => _refresh(force: true),
                    tooltip: tr(context, 'Обновить', 'Refresh'),
                    label: tr(context, 'Обновить', 'Refresh'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty)
            _EmptyPanel(
              title: tr(context, 'Выберите группу', 'Choose a group'),
              detail: tr(
                context,
                'Выберите группу в меню действий аккаунта на экране посещаемости.',
                'Assign a group to an account using its actions menu on the attendance screen.',
              ),
            )
          else ...[
            AppActionMenu(
              entries: [
                for (final entry in groups.entries)
                  CampusMenuEntry(value: entry.key, label: entry.value),
              ],
              onSelected: (value) {
                final id = value as int;
                setState(() => _groupId = id);
                widget.onGroupChanged?.call(id);
                _refresh();
              },
              anchorBuilder: (context, open) => InkWell(
                onTap: open,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.zero,
                    border: Border.all(color: context.palette.line),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          groups[_groupId] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w400),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                Text(
                  '${_date(week)} — ${_date(week.add(const Duration(days: 6)))}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
                Row(
                  children: [
                    Expanded(
                      child: CampusTextAction(
                        onPressed: () =>
                            _selectDay(_day.subtract(const Duration(days: 7))),
                        tooltip: tr(
                          context,
                          'Предыдущая неделя',
                          'Previous week',
                        ),
                        label: tr(context, 'назад', 'previous'),
                      ),
                    ),
                    Expanded(
                      child: CampusTextAction(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: DateTime(
                              _day.year,
                              _day.month,
                              _day.day,
                            ),
                            firstDate: DateTime(today.year - 1),
                            lastDate: DateTime(today.year + 2),
                          );
                          if (date != null && mounted) {
                            _selectDay(
                              DateTime.utc(date.year, date.month, date.day),
                            );
                          }
                        },
                        tooltip: tr(context, 'Выбрать дату', 'Choose date'),
                        label: tr(context, 'дата', 'date'),
                      ),
                    ),
                    Expanded(
                      child: CampusTextAction(
                        onPressed: () =>
                            _selectDay(_day.add(const Duration(days: 7))),
                        tooltip: tr(context, 'Следующая неделя', 'Next week'),
                        label: tr(context, 'вперёд', 'next'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var index = 0; index < 7; index++)
                  Expanded(
                    child: _DayButton(
                      date: week.add(Duration(days: index)),
                      label: dayNames[index],
                      selected: _sameDay(week.add(Duration(days: index)), _day),
                      today: _sameDay(week.add(Duration(days: index)), today),
                      hasLessons: _lessons.any(
                        (lesson) => _sameDay(
                          lesson.start,
                          week.add(Duration(days: index)),
                        ),
                      ),
                      onTap: () => _selectDay(week.add(Duration(days: index))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
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
                if (!_sameDay(_day, today))
                  CampusButton.text(
                    onPressed: () => _selectDay(today),
                    child: Text(tr(context, 'Сегодня', 'Today')),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_error != null && dailyLessons.isNotEmpty) ...[
              Text(_error!, style: TextStyle(color: context.palette.muted)),
              const SizedBox(height: 12),
            ],
            if (_sameDay(_day, today) &&
                dailyLessons.any((lesson) => lesson.end.isAfter(now))) ...[
              CampusPanel(
                child: Builder(
                  builder: (context) {
                    final lesson = dailyLessons.firstWhere(
                      (lesson) => lesson.end.isAfter(now),
                    );
                    final current = !lesson.start.isAfter(now);
                    final minutes = (current ? lesson.end : lesson.start)
                        .difference(now)
                        .inMinutes;
                    return CampusListItem(
                      headline: lesson.subject,
                      supportingText:
                          '${current ? tr(context, 'Сейчас', 'Now') : tr(context, 'Следующая пара', 'Next class')} · ${_time(lesson.start)}–${_time(lesson.end)} · ${lesson.location}',
                      trailing: Text(
                        trf(context, '{minutes} мин', '{minutes} min', {
                          'minutes': minutes,
                        }),
                      ),
                      onTap: () => _openLesson(lesson, groupAccounts),
                    );
                  },
                ),
              ),
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
                _LessonRow(
                  lesson: dailyLessons[index],
                  confirmed: _confirmed(dailyLessons[index]),
                  time: _time(dailyLessons[index].start),
                  endTime: _time(dailyLessons[index].end),
                  isCurrent:
                      _sameDay(_day, today) &&
                      !now.isBefore(dailyLessons[index].start) &&
                      now.isBefore(dailyLessons[index].end),
                  onTap: () => _openLesson(dailyLessons[index], groupAccounts),
                  onRoom: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => CampusMapsPage(
                        room: dailyLessons[index].location,
                        lessons: dailyLessons,
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

class _DayButton extends StatelessWidget {
  const _DayButton({
    required this.date,
    required this.label,
    required this.selected,
    required this.today,
    required this.hasLessons,
    required this.onTap,
  });
  final DateTime date;
  final String label;
  final bool selected;
  final bool today;
  final bool hasLessons;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: CampusPressable(
      child: Material(
        animationDuration: Duration.zero,
        color: selected ? context.palette.selectionSurface : Colors.transparent,
        borderRadius: BorderRadius.zero,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? context.palette.blue.withValues(alpha: .75)
                        : context.palette.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: selected
                        ? context.palette.blue
                        : context.palette.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: today ? 6 : 5,
                  height: today ? 6 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasLessons
                        ? (selected
                              ? context.palette.blue
                              : context.palette.blue)
                        : (today
                              ? (selected
                                    ? context.palette.blue.withValues(
                                        alpha: .75,
                                      )
                                    : context.palette.line)
                              : Colors.transparent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
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
    final accent = context.palette.ink;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                Text(
                  endTime,
                  style: TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 11,
                    height: 1.4,
                    color: context.palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CampusPressable(
            child: Material(
              color: context.palette.surface,
              borderRadius: BorderRadius.zero,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.zero,
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.zero,
                    border: Border(
                      bottom: BorderSide(
                        color: isCurrent ? accent : context.palette.line,
                        width: .5,
                      ),
                    ),
                    color: isCurrent
                        ? context.palette.selectionSurface
                        : context.palette.surface,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lesson.subject,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                      if (isCurrent) ...[
                        const SizedBox(height: 6),
                        Text(
                          tr(context, '● Сейчас', '● Now'),
                          style: TextStyle(
                            color: context.palette.blue,
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                      if (lesson.type.isNotEmpty || lesson.location.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (lesson.type.isNotEmpty)
                              Text(
                                lesson.type,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.palette.muted,
                                ),
                              ),
                            if (lesson.location.isNotEmpty)
                              TextButton(
                                onPressed: onRoom,
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                ),
                                child: Text(
                                  lesson.location,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              confirmed.isEmpty
                                  ? tr(
                                      context,
                                      'Нет отметок',
                                      'No confirmations',
                                    )
                                  : confirmed
                                        .map((mark) => mark.accountLabel)
                                        .join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: confirmed.isEmpty
                                    ? context.palette.muted
                                    : context.palette.success,
                                fontWeight: confirmed.isEmpty
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: BorderRadius.zero,
    ),
    child: Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 5),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.palette.muted, fontSize: 13),
        ),
      ],
    ),
  );
}
