import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'accounts.dart';
import 'aa_id.dart';
import 'server_api.dart';
import 'server_sessions.dart';
import 'app_settings.dart';
import 'attendance_log.dart';
import 'schedule_api.dart';
import 'translations.dart';

const studySummaryChannel = MethodChannel('antiattendance/study_summary');

String summaryText(String language, String english, String russian) {
  if (language == 'ru') return russian;
  final value = translations[english];
  return switch (language) {
    'fr' => value?.$1 ?? english,
    'pt' => value?.$2 ?? english,
    'zh' => value?.$3 ?? english,
    _ => english,
  };
}

DateTime moscowCivilTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 3));
DateTime moscowInstant(DateTime civil) => DateTime.utc(
  civil.year,
  civil.month,
  civil.day,
  civil.hour,
  civil.minute,
  civil.second,
).subtract(const Duration(hours: 3));
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

List<Map<String, Object?>> buildStudySummaries({
  required List<SavedAccount> accounts,
  required List<ScheduleLesson> lessons,
  required List<AttendanceMark> marks,
  required DateTime now,
  String language = 'en',
}) {
  final today = moscowCivilTime(now);
  final days = <String, List<ScheduleLesson>>{};
  final groups = accounts.map((a) => a.groupId).whereType<int>().toSet();
  for (final lesson in lessons) {
    if (!groups.contains(lesson.groupId)) continue;
    final day = DateTime.utc(
      lesson.start.year,
      lesson.start.month,
      lesson.start.day,
    );
    if (day.isBefore(DateTime.utc(today.year, today.month, today.day))) {
      continue;
    }
    final key =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    days.putIfAbsent(key, () => []).add(lesson);
  }
  final result = <Map<String, Object?>>[];
  for (final entry in days.entries) {
    final dayLessons = entry.value..sort((a, b) => a.start.compareTo(b.start));
    final end = dayLessons
        .map((l) => l.end)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final people = <Map<String, Object?>>[];
    for (final account in accounts) {
      final own = dayLessons
          .where((l) => l.groupId == account.groupId)
          .toList();
      final ownMarks = marks
          .where(
            (m) =>
                m.accountId == account.id &&
                _sameDay(moscowCivilTime(m.at), end),
          )
          .toList();
      final confirmed = ownMarks
          .map((m) => m.lessonKey)
          .whereType<String>()
          .toSet();
      final count = own.where((l) => confirmed.contains(l.key)).length;
      final classLines = own
          .map(
            (l) =>
                '${confirmed.contains(l.key) ? '✓' : '○'} ${_time(l.start)} ${l.subject} · ${summaryText(language, confirmed.contains(l.key) ? 'Confirmed' : 'Not recorded', confirmed.contains(l.key) ? 'Подтверждено' : 'Не записано')}',
          )
          .toList();
      if (own.isEmpty) {
        classLines.add(
          summaryText(
            language,
            account.groupId == null
                ? 'Assign a group to include classes.'
                : 'No classes today',
            account.groupId == null
                ? 'Назначьте группу для списка занятий.'
                : 'Сегодня нет занятий',
          ),
        );
      }
      final unlinked = ownMarks.where((m) => m.lessonKey == null).length;
      if (unlinked > 0) {
        classLines.add(
          '${summaryText(language, 'Other confirmations', 'Другие подтверждения')}: $unlinked',
        );
      }
      people.add({
        'name': account.label,
        'accountId': account.id,
        'lines': classLines,
        'counts': '$count/${own.length}',
        'sessionExpired': account.sessionExpired,
        'sessionExpiresAt': account.expiresAt?.millisecondsSinceEpoch,
      });
    }
    result.add({
      'id': entry.key,
      'at': moscowInstant(end).millisecondsSinceEpoch,
      'title': summaryText(language, 'Study day summary', 'Итоги учебного дня'),
      'recorded': summaryText(language, 'Confirmed', 'Подтверждено'),
      'sessionReminder': summaryText(
        language,
        'Sign-in needed',
        'Нужно войти снова',
      ),
      'people': people,
    });
  }
  result.sort((a, b) => (a['at'] as int).compareTo(b['at'] as int));
  return result;
}

List<Map<String, Object?>> buildServerStudySummary(
  Map<String, dynamic> data, {
  String language = 'en',
}) {
  final lessons = serverRows(data['lessons']);
  if (lessons.isEmpty) return [];
  final date = '${data['date']}'.split('.');
  if (date.length != 3) throw const FormatException('Invalid study date');
  final day = DateTime.utc(
    int.parse(date[2]),
    int.parse(date[1]),
    int.parse(date[0]),
  );
  DateTime endOf(Map<String, dynamic> lesson) {
    final parts = '${lesson['end']}'.split(':');
    return DateTime.utc(
      day.year,
      day.month,
      day.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  final end = lessons.map(endOf).reduce((a, b) => a.isAfter(b) ? a : b);
  return [
    {
      'id': day.toIso8601String().substring(0, 10),
      'at': moscowInstant(end).millisecondsSinceEpoch,
      'title': summaryText(language, 'Study day summary', 'Итоги учебного дня'),
      'recorded': summaryText(language, 'Confirmed', 'Подтверждено'),
      'sessionReminder': summaryText(
        language,
        'Sign-in needed',
        'Нужно войти снова',
      ),
      'people': [
        for (final person in serverRows(data['people']))
          {
            'name': person['label'] ?? person['username'] ?? '—',
            'accountId': person['id'],
            'sessionExpired': person['session'] == 'expired',
            'counts':
                '${lessons.where((l) => dayMark(l, '${person['id']}')?['state'] == 'approved').length}/${lessons.length}',
            'lines': [
              for (final lesson in lessons)
                '${lesson['start']} ${lesson['subject']} · ${dayMark(lesson, '${person['id']}')?['message'] ?? dayMark(lesson, '${person['id']}')?['state'] ?? '—'}',
            ],
          },
      ],
    },
  ];
}

class StudySummaryService {
  StudySummaryService({
    ScheduleApi? api,
    AccountStore? accounts,
    AttendanceLogStore? log,
    AppSettingsStore? settings,
  }) : _api = api ?? ScheduleApi(),
       _accounts = accounts ?? AccountStore(),
       _log = log ?? AttendanceLogStore(),
       _settings = settings ?? AppSettingsStore(),
       _ownsApi = api == null;
  final ScheduleApi _api;
  final AccountStore _accounts;
  final AttendanceLogStore _log;
  final AppSettingsStore _settings;
  final bool _ownsApi;

  Future<void> sync() async {
    if (!Platform.isAndroid) return;
    final enabled = await _settings.loadDaySummaryEnabled();
    if (!enabled) {
      await studySummaryChannel.invokeMethod('configure', {'enabled': false});
      return;
    }
    if (_ownsApi) {
      await AaId.initialize();
      await ServerSessions.initialize();
      final server = ServerSessions.active;
      if (server != null) {
        await server.fetch();
        if (server.serverManaged) {
          final data = await AaServerApi(server).today();
          if (data['schedule_error'] != null) {
            throw StateError('Schedule unavailable');
          }
          final language =
              await _settings.loadLanguage() ??
              Platform.localeName.split('_').first;
          final tasks = buildServerStudySummary(data, language: language);
          if (await _settings.loadDaySummaryEnabled()) {
            await studySummaryChannel.invokeMethod('configure', {
              'enabled': true,
              'tasks': tasks,
            });
          }
          return;
        }
      }
    }
    final accounts = await _accounts.load();
    final marks = await _log.load();
    final language =
        await _settings.loadLanguage() ?? Platform.localeName.split('_').first;
    final now = DateTime.now();
    final today = moscowCivilTime(now);
    final week = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - 1));
    final lessons = <ScheduleLesson>[];
    for (final group
        in accounts.map((a) => a.groupId).whereType<int>().toSet()) {
      for (var offset = 0; offset < 5; offset++) {
        lessons.addAll(
          await _api.lessonsForWeek(
            group,
            week.add(Duration(days: offset * 7)),
          ),
        );
      }
    }
    final tasks = buildStudySummaries(
      accounts: accounts,
      lessons: lessons,
      marks: marks,
      now: now,
      language: language,
    );
    if (!await _settings.loadDaySummaryEnabled()) return;
    await studySummaryChannel.invokeMethod('configure', {
      'enabled': true,
      'tasks': tasks,
    });
  }

  void close() {
    if (_ownsApi) _api.close();
  }
}

Future<void> runStudySummaryBackground() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = StudySummaryService();
  var success = false;
  try {
    await service.sync();
    success = true;
  } finally {
    service.close();
    await studySummaryChannel.invokeMethod('finished', {'success': success});
  }
}
