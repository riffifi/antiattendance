import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';
import 'campus_design.dart';
import 'icons/campus_icon.dart';
import 'l10n.dart';
import 'pass_people.dart';
import 'server_sessions.dart';

/// Today's lessons of the person's group with everyone's marks, the same as
/// the site's /today page. Another group joins a lesson only when it was at
/// that same class.
class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.active});

  /// Refreshes only while the screen is shown.
  final bool active;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _noServer = false;
  bool _loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(TodayPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _start();
    if (!widget.active) _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _load();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  Future<void> _load() async {
    final server = ServerSessions.active;
    if (server == null) {
      // Shown by build(): initState must not read the locale.
      _noServer = true;
      return;
    }
    if (_loading) return;
    _loading = true;
    try {
      final data = await server.today();
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = serverError(context, error));
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final error = _noServer
        ? tr(
            context,
            'Подключитесь к серверу AntiAttendance в настройках.',
            'Connect to the AntiAttendance server in Settings.',
          )
        : _error;
    final lessons = [
      for (final lesson in data?['lessons'] as List? ?? const [])
        if (lesson is Map<String, dynamic>) lesson,
    ];
    final people = [
      for (final person in data?['people'] as List? ?? const [])
        if (person is Map<String, dynamic>) person,
    ];
    final journalErrors = {
      for (final journal in (data?['mirea'] as Map? ?? const {}).values)
        if (journal is Map && journal['error'] is String)
          journal['error'] as String,
    };
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            tr(context, 'Отметки за день', 'Marks today'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (data?['date'] is String) data!['date'] as String,
              if (data?['group_name'] is String) data!['group_name'] as String,
            ].join(' · '),
            style: TextStyle(color: context.palette.muted),
          ),
          const SizedBox(height: 20),
          if (data == null && error == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CampusProgress.compact()),
            ),
          if (error != null) _note(context, error, error: true),
          if (data != null && data['group_id'] == null)
            _note(
              context,
              tr(
                context,
                'Группа не определена. Войдите в AA ID с аккаунтом МИРЭА.',
                'Your group is unknown. Sign in to AA ID with a MIREA account.',
              ),
            ),
          if (data?['schedule_error'] is String)
            _note(context, data!['schedule_error'] as String, error: true),
          if (data != null &&
              data['group_id'] != null &&
              data['schedule_error'] == null &&
              lessons.isEmpty)
            _note(
              context,
              tr(context, 'Сегодня пар нет.', 'No lessons today.'),
            ),
          for (final lesson in lessons) _Lesson(lesson: lesson, people: people),
          if (data != null && lessons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              [
                if ((data['mirea'] as Map? ?? const {}).isNotEmpty)
                  tr(
                    context,
                    'Статусы из журнала МИРЭА обновляются раз в 2 минуты.',
                    'MIREA journal statuses refresh every 2 minutes.',
                  ),
                if (journalErrors.isNotEmpty)
                  '${tr(context, 'МИРЭА', 'MIREA')}: ${journalErrors.join('; ')}.',
              ].join(' '),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.palette.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text, {bool error = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          text,
          style: TextStyle(
            color: error
                ? Theme.of(context).colorScheme.error
                : context.palette.muted,
          ),
        ),
      );
}

class _Lesson extends StatelessWidget {
  const _Lesson({required this.lesson, required this.people});
  final Map<String, dynamic> lesson;
  final List<Map<String, dynamic>> people;

  /// The Pulse journal wins when it is definite: present or excused at any
  /// time, absent once the lesson is over (during it everyone is absent
  /// until marked).
  (String, _Tone, String) _cell(BuildContext context, String id) {
    final mark = (lesson['marks'] as Map?)?[id] as Map?;
    final mirea = (lesson['mirea'] as Map?)?[id];
    final approved = mark?['state'] == 'approved';
    if (mirea == 'present') {
      return (
        '✓',
        _Tone.ok,
        tr(context, 'Отмечен в журнале МИРЭА', 'Marked in the MIREA journal'),
      );
    }
    if (mirea == 'excused') {
      return ('У', _Tone.wait, tr(context, 'Уважительная причина', 'Excused'));
    }
    if (mirea == 'absent' && lesson['state'] == 'past' && !approved) {
      return (
        '✗',
        _Tone.bad,
        tr(
          context,
          'Отсутствовал по журналу МИРЭА',
          'Absent in the MIREA journal',
        ),
      );
    }
    if (mark == null) {
      return ('—', _Tone.none, tr(context, 'Не отмечался', 'No attempt'));
    }
    final time = mark['created'] is num
        ? ', ${_clock(mark['created'] as num)}'
        : '';
    return switch (mark['state']) {
      'approved' => ('✓', _Tone.ok, tr(context, 'Отмечен', 'Marked') + time),
      'waiting' => (
        '…',
        _Tone.wait,
        tr(context, 'Ждёт подтверждения', 'Waiting') + time,
      ),
      'expired' => (
        '✗',
        _Tone.bad,
        tr(context, 'Сессия истекла', 'Session expired') + time,
      ),
      'error' => ('✗', _Tone.bad, tr(context, 'Ошибка', 'Error') + time),
      _ => ('✗', _Tone.bad, tr(context, 'Не отмечен', 'Not marked') + time),
    };
  }

  static String _clock(num seconds) {
    // Lesson times are Moscow time; so are the marks.
    final moment = DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).round(),
      isUtc: true,
    ).add(const Duration(hours: 3));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(moment.hour)}:${two(moment.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final marks = lesson['marks'] as Map? ?? const {};
    final here = [
      for (final person in people)
        if (marks.containsKey(person['id'])) person,
    ];
    final counted = [
      for (final person in here)
        if (_cell(context, person['id'] as String).$2 == _Tone.ok) person,
    ].length;
    final state = lesson['state'];
    final groups = [
      for (final group in lesson['groups'] as List? ?? const [])
        if (group is Map && group['name'] is String) group['name'] as String,
    ];
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: CampusPanel(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        color: state == 'now' ? palette.surface : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '${lesson['start']}–${lesson['end']}',
                  style: const TextStyle(fontFamily: 'GeistMono', fontSize: 13),
                ),
                if (state == 'now') ...[
                  const SizedBox(width: 8),
                  Text(
                    tr(context, 'сейчас', 'now'),
                    style: TextStyle(color: palette.blue, fontSize: 13),
                  ),
                ],
                const Spacer(),
                if (here.isNotEmpty)
                  Text(
                    '$counted / ${here.length}',
                    style: TextStyle(
                      fontFamily: 'GeistMono',
                      fontSize: 13,
                      color: palette.muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              lesson['subject'] as String? ?? '',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: state == 'past' ? palette.muted : null),
            ),
            Text(
              [
                    lesson['type'],
                    lesson['location'],
                    if (groups.length > 1) groups.join(', '),
                  ]
                  .whereType<String>()
                  .where((part) => part.isNotEmpty)
                  .join(' · '),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: palette.muted),
            ),
            const SizedBox(height: 8),
            for (final person in here)
              _PersonRow(
                person: person,
                cell: _cell(context, person['id'] as String),
              ),
          ],
        ),
      ),
    );
  }
}

enum _Tone { ok, wait, bad, none }

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.cell});
  final Map<String, dynamic> person;
  final (String, _Tone, String) cell;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (symbol, tone, title) = cell;
    final color = switch (tone) {
      _Tone.ok => palette.blue,
      _Tone.bad => Theme.of(context).colorScheme.error,
      _ => palette.muted,
    };
    return Semantics(
      label: '${person['label']}: $title',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              // Icons for ✓ and ✗: the app's fonts have no such glyphs.
              child: switch (symbol) {
                '✓' => CampusIcon(Icons.check_rounded, size: 18, color: color),
                '✗' => CampusIcon(Icons.close_rounded, size: 18, color: color),
                _ => Text(
                  symbol,
                  style: TextStyle(
                    fontFamily: 'GeistMono',
                    fontSize: 15,
                    color: color,
                  ),
                ),
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person['label'] as String? ?? '',
                    style: TextStyle(
                      fontWeight: person['own'] == true
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                  Text(
                    [
                      title,
                      if (person['session'] != 'valid')
                        tr(context, 'не подключён', 'not connected'),
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: palette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
