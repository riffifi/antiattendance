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
  final DateTime? initialDay;
  final int? initialGroupId;
  final ValueChanged<DateTime>? onDayChanged;
  final ValueChanged<int>? onGroupChanged;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage>
    with SingleTickerProviderStateMixin {
  int? _groupId;
  late DateTime _day = widget.initialDay ?? _today();
  List<ScheduleLesson> _lessons = [];
  List<AttendanceMark> _marks = [];
  bool _loading = false;
  String? _error;
  int _generation = 0;
  Timer? _clock;
  late final AnimationController _refreshRotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

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
      if (mounted) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _refreshRotation.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.accounts.map((account) => account.groupId).toSet();
    if (_groupId == null || !ids.contains(_groupId)) {
      _groupId = _firstGroup();
      _refresh();
    }
  }

  Future<void> _refresh({bool force = false}) async {
    final generation = ++_generation;
    final groupId = _groupId;
    _refreshRotation.repeat();
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
        _refreshRotation.stop();
        _refreshRotation.reset();
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
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
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
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lesson.subject,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
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
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    tr(context, 'Подтверждены Пульсом', 'Confirmed by Pulse'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (confirmed.isEmpty)
                    Text(
                      tr(context, 'Пока никого', 'Nobody yet'),
                      style: const TextStyle(color: AppColors.muted),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final mark in confirmed)
                          Chip(
                            avatar: const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Color(0xFF238664),
                            ),
                            label: Text(mark.accountLabel),
                            backgroundColor: AppColors.mint,
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: groupAccounts.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              Platform.isAndroid || Platform.isIOS
                                  ? 'scan'
                                  : 'paste',
                            ),
                      icon: Icon(
                        Platform.isAndroid || Platform.isIOS
                            ? Icons.qr_code_scanner_rounded
                            : Icons.link_rounded,
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
                      child: TextButton.icon(
                        onPressed: groupAccounts.isEmpty
                            ? null
                            : () => Navigator.pop(context, 'paste'),
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: Text(
                          tr(context, 'Вставить ссылку', 'Paste link'),
                        ),
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
    final dayNames = Localizations.localeOf(context).languageCode == 'ru'
        ? const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dateText = MaterialLocalizations.of(context)
        .formatMediumDate(DateTime(_day.year, _day.month, _day.day));
    return RefreshIndicator(
      onRefresh: () => _refresh(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'Расписание', 'Schedule'),
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton.filled(
                onPressed: groups.isEmpty || _loading
                    ? null
                    : () => _refresh(force: true),
                style: IconButton.styleFrom(
                  disabledBackgroundColor: _loading
                      ? AppColors.blue
                      : AppColors.line,
                  disabledForegroundColor: _loading
                      ? Colors.white
                      : AppColors.muted,
                ),
                icon: RotationTransition(
                  turns: _refreshRotation,
                  child: const Icon(Icons.refresh_rounded),
                ),
                tooltip: tr(context, 'Обновить', 'Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            tr(
              context,
              'Подтверждения Пульса на этом устройстве',
              'Pulse confirmations on this device',
            ),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (groups.isEmpty)
            _EmptyPanel(
              icon: Icons.group_add_outlined,
              title: tr(context, 'Выберите группу', 'Choose a group'),
              detail: tr(
                context,
                'Назначьте группу аккаунту через меню ⋮ на вкладке посещаемости.',
                'Assign a group to an account using the ⋮ menu on the attendance tab.',
              ),
            )
          else ...[
            PopupMenuButton<int>(
              onSelected: (id) {
                setState(() => _groupId = id);
                widget.onGroupChanged?.call(id);
                _refresh();
              },
              itemBuilder: (_) => [
                for (final entry in groups.entries)
                  PopupMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.groups_rounded,
                      color: AppColors.blue,
                      size: 21,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        groups[_groupId] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  onPressed: () =>
                      _selectDay(_day.subtract(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: tr(context, 'Предыдущая неделя', 'Previous week'),
                ),
                Expanded(
                  child: Text(
                    '${_date(week)} — ${_date(week.add(const Duration(days: 6)))}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      _selectDay(_day.add(const Duration(days: 7))),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: tr(context, 'Следующая неделя', 'Next week'),
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
            const SizedBox(height: 24),
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
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!_loading && _error == null)
                        Text(
                          '${_sameDay(_day, today) ? '$dateText · ' : ''}'
                          '${tr(context, '${dailyLessons.length} занятий', '${dailyLessons.length} classes')}',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!_sameDay(_day, today))
                  TextButton(
                    onPressed: () => _selectDay(today),
                    child: Text(tr(context, 'Сегодня', 'Today')),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading) ...[
              const SizedBox(height: 25),
              const Center(child: CircularProgressIndicator()),
            ] else if (_error != null) ...[
              _EmptyPanel(
                icon: Icons.wifi_off_rounded,
                title: _error!,
                detail: tr(
                  context,
                  'Потяните вниз или нажмите обновить.',
                  'Pull down or tap refresh to retry.',
                ),
              ),
            ] else if (dailyLessons.isEmpty) ...[
              _EmptyPanel(
                icon: Icons.event_available_rounded,
                title: tr(context, 'Свободный день', 'A free day'),
                detail: tr(
                  context,
                  'На этот день занятий нет.',
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
                ),
              ],
            ],
            if (dayConfirmations.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                tr(context, 'Другие подтверждения', 'Other confirmations'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              Text(
                dayConfirmations
                    .map((mark) => mark.accountLabel)
                    .toSet()
                    .join(', '),
                style: const TextStyle(color: AppColors.muted),
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
    child: Material(
      color: selected ? AppColors.blue : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
                  color: selected ? Colors.white70 : AppColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: today ? 6 : 5,
                height: today ? 6 : 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasLessons
                      ? (selected ? Colors.white : AppColors.blue)
                      : (today
                            ? (selected ? Colors.white70 : AppColors.line)
                            : Colors.transparent),
                ),
              ),
            ],
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
  });
  final ScheduleLesson lesson;
  final List<AttendanceMark> confirmed;
  final String time;
  final String endTime;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent =
        lesson.type.toLowerCase().contains('лаб') ||
            lesson.type.toLowerCase().contains('lab')
        ? const Color(0xFF2B9A75)
        : lesson.type.toLowerCase().contains('пр') ||
              lesson.type.toLowerCase().contains('prac')
        ? const Color(0xFFBE7B2B)
        : AppColors.blue;
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  endTime,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Material(
            color: isCurrent ? const Color(0xFFEDF4FF) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: accent, width: 4)),
                  borderRadius: BorderRadius.circular(16),
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
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.muted,
                          size: 20,
                        ),
                      ],
                    ),
                    if (isCurrent) ...[
                      const SizedBox(height: 6),
                      Text(
                        tr(context, '● Сейчас', '● Now'),
                        style: const TextStyle(
                          color: AppColors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (lesson.type.isNotEmpty ||
                        lesson.location.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        [
                          lesson.type,
                          lesson.location,
                        ].where((value) => value.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          confirmed.isEmpty
                              ? Icons.radio_button_unchecked_rounded
                              : Icons.check_circle_rounded,
                          color: confirmed.isEmpty
                              ? AppColors.muted
                              : const Color(0xFF238664),
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            confirmed.isEmpty
                                ? tr(
                                    context,
                                    'Нет подтверждений',
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
                                  ? AppColors.muted
                                  : const Color(0xFF238664),
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
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        Icon(icon, color: AppColors.blue, size: 30),
        const SizedBox(height: 10),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 5),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
      ],
    ),
  );
}
