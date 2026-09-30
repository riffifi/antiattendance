import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:rrule/rrule.dart';

const _scheduleHost = 'schedule-of.mirea.ru';

class ScheduleGroup {
  const ScheduleGroup({required this.id, required this.name});
  final int id;
  final String name;
}

class ScheduleLesson {
  const ScheduleLesson({
    required this.key,
    required this.groupId,
    required this.start,
    required this.end,
    required this.subject,
    required this.type,
    required this.location,
    required this.teachers,
  });

  final String key;
  final int groupId;
  // Civil Moscow date/time stored as UTC fields so display is stable on phones
  // configured for a different timezone.
  final DateTime start;
  final DateTime end;
  final String subject;
  final String type;
  final String location;
  final String teachers;
}

class ScheduleApi {
  ScheduleApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  final _calendarCache = <int, (DateTime, String)>{};

  Future<List<ScheduleGroup>> searchGroups(String query) async {
    final q = query.trim();
    if (q.length < 2 || q.length > 60) return [];
    final uri = Uri.https(_scheduleHost, '/schedule/api/search', {
      'limit': '20',
      'match': q,
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw FormatException('Schedule search HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
      throw const FormatException('Invalid group search response.');
    }
    return [
      for (final item in decoded['data'] as List)
        if (item is Map<String, dynamic> &&
            item['scheduleTarget'] == 1 &&
            item['id'] is int &&
            item['targetTitle'] is String)
          ScheduleGroup(
            id: item['id'] as int,
            name: item['targetTitle'] as String,
          ),
    ];
  }

  Future<List<ScheduleLesson>> lessonsForWeek(
    int groupId,
    DateTime weekStart, {
    bool refresh = false,
  }) async {
    if (groupId <= 0) throw const FormatException('Invalid group.');
    final cached = _calendarCache[groupId];
    String source;
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 15)) {
      source = cached.$2;
    } else {
      final uri = Uri.https(
        _scheduleHost,
        '/schedule/api/ical/Group/$groupId',
        {'includeMeta': 'true'},
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw FormatException('Schedule HTTP ${response.statusCode}');
      }
      if (response.bodyBytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Schedule response is too large.');
      }
      source = utf8.decode(response.bodyBytes);
      if (!source.contains('BEGIN:VCALENDAR')) {
        throw const FormatException('Invalid schedule response.');
      }
      _calendarCache[groupId] = (DateTime.now(), source);
    }
    return parseGroupCalendar(source, groupId, weekStart);
  }

  void close() => _client.close();
}

List<ScheduleLesson> parseGroupCalendar(
  String source,
  int groupId,
  DateTime weekStart,
) {
  final from = DateTime.utc(weekStart.year, weekStart.month, weekStart.day);
  final to = from.add(const Duration(days: 7));
  final lessons = <String, ScheduleLesson>{};
  final unfolded = source.replaceAll(RegExp(r'\r?\n[ \t]'), '');
  Map<String, List<String>>? event;
  for (final line in const LineSplitter().convert(unfolded)) {
    if (line == 'BEGIN:VEVENT') {
      event = <String, List<String>>{};
      continue;
    }
    if (line == 'END:VEVENT') {
      if (event != null) {
        for (final lesson in _eventLessons(event, groupId, from, to)) {
          lessons[lesson.key] = lesson;
        }
      }
      event = null;
      continue;
    }
    if (event == null) continue;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final key = line.substring(0, colon).split(';').first.toUpperCase();
    event.putIfAbsent(key, () => []).add(_unescape(line.substring(colon + 1)));
  }
  final result = lessons.values.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return result;
}

Iterable<ScheduleLesson> _eventLessons(
  Map<String, List<String>> event,
  int groupId,
  DateTime from,
  DateTime to,
) sync* {
  String? field(String key) => event[key]?.firstOrNull;
  if (field('TRANSP') == 'TRANSPARENT') return;
  final baseStart = _parseIcsDate(field('DTSTART'));
  final baseEnd = _parseIcsDate(field('DTEND'));
  if (baseStart == null || baseEnd == null) return;
  final duration = baseEnd.difference(baseStart);
  if (duration <= Duration.zero || duration > const Duration(days: 1)) return;
  final starts = <DateTime>[];
  final rule = field('RRULE');
  if (rule == null) {
    starts.add(baseStart);
  } else {
    if (!baseStart.isBefore(to)) return;
    try {
      starts.addAll(
        RecurrenceRule.fromString('RRULE:$rule').getInstances(
          start: baseStart,
          after: from.isAfter(baseStart) ? from : baseStart,
          includeAfter: true,
          before: to,
        ),
      );
    } on FormatException {
      return;
    }
  }
  for (final raw in event['RDATE'] ?? const <String>[]) {
    starts.addAll(raw.split(',').map(_parseIcsDate).whereType<DateTime>());
  }
  final excluded = <DateTime>{
    for (final raw in event['EXDATE'] ?? const <String>[])
      ...raw.split(',').map(_parseIcsDate).whereType<DateTime>(),
  };
  final uid = field('UID') ?? '';
  final subject = field('X-META-DISCIPLINE') ?? field('SUMMARY') ?? '';
  if (subject.isEmpty) return;
  final type = field('X-META-LESSON_TYPE') ?? '';
  final location = field('LOCATION') ?? '';
  final teachers = (event['X-META-TEACHER'] ?? const <String>[]).join(', ');
  for (final start in starts.toSet()) {
    if (start.isBefore(from) ||
        !start.isBefore(to) ||
        excluded.contains(start)) {
      continue;
    }
    final stamp =
        '${start.year.toString().padLeft(4, '0')}${start.month.toString().padLeft(2, '0')}${start.day.toString().padLeft(2, '0')}${start.hour.toString().padLeft(2, '0')}${start.minute.toString().padLeft(2, '0')}';
    yield ScheduleLesson(
      key: '$groupId:$uid:$stamp',
      groupId: groupId,
      start: start,
      end: start.add(duration),
      subject: subject,
      type: type,
      location: location,
      teachers: teachers,
    );
  }
}

DateTime? _parseIcsDate(String? text) {
  if (text == null) return null;
  final match = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?Z?$')
      .firstMatch(text);
  if (match == null) return null;
  return DateTime.utc(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );
}

String _unescape(String text) => text
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\');
