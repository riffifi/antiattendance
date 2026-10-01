import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AttendanceMark {
  const AttendanceMark({
    required this.accountId,
    required this.accountLabel,
    required this.at,
    this.groupId,
    this.lessonKey,
    this.pulseLessonId,
  });

  final String accountId;
  final String accountLabel;
  final DateTime at;
  final int? groupId;
  final String? lessonKey;
  final String? pulseLessonId;

  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'accountLabel': accountLabel,
    'at': at.toIso8601String(),
    'groupId': groupId,
    'lessonKey': lessonKey,
    'pulseLessonId': pulseLessonId,
  };

  factory AttendanceMark.fromJson(Map<String, dynamic> json) => AttendanceMark(
    accountId: json['accountId'] as String,
    accountLabel: json['accountLabel'] as String,
    at: DateTime.parse(json['at'] as String),
    groupId: json['groupId'] as int?,
    lessonKey: json['lessonKey'] as String?,
    pulseLessonId: json['pulseLessonId'] as String?,
  );
}

class AttendanceLogStore {
  AttendanceLogStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'attendance_marks_v1';

  Future<List<AttendanceMark>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((item) => AttendanceMark.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> _pending = Future.value();

  Future<void> add(AttendanceMark mark) {
    final result = _pending.then((_) => _addNow(mark));
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> flush() => _pending;

  Future<void> _addNow(AttendanceMark mark) async {
    final marks = await load();
    if (marks.any(
      (item) =>
          item.accountId == mark.accountId &&
          ((mark.lessonKey != null && item.lessonKey == mark.lessonKey) ||
              (mark.pulseLessonId != null &&
                  item.pulseLessonId == mark.pulseLessonId)),
    )) {
      return;
    }
    marks.add(mark);
    await _storage.write(key: _key, value: jsonEncode(marks));
  }
}

class AttendanceCounts {
  const AttendanceCounts({
    required this.total,
    required this.week,
    required this.today,
  });

  final int total;
  final int week;
  final int today;

  static const zero = AttendanceCounts(total: 0, week: 0, today: 0);

  static Map<String, AttendanceCounts> fromMarks(
    List<AttendanceMark> marks, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final localNow = current.toLocal();
    final todayStart = DateTime(localNow.year, localNow.month, localNow.day);
    final weekStart = DateTime(
      localNow.year,
      localNow.month,
      localNow.day - localNow.weekday + 1,
    );
    final total = <String, int>{};
    final week = <String, int>{};
    final today = <String, int>{};
    final seenLessons = <String, Set<String>>{};
    for (final mark in marks) {
      final keys = <String>{
        if (mark.pulseLessonId != null) 'pulse:${mark.pulseLessonId}',
        if (mark.lessonKey != null) 'schedule:${mark.lessonKey}',
      };
      final seen = seenLessons.putIfAbsent(mark.accountId, () => {});
      if (keys.any(seen.contains)) {
        continue;
      }
      seen.addAll(keys);
      total.update(mark.accountId, (value) => value + 1, ifAbsent: () => 1);
      final at = mark.at.toLocal();
      if (!at.isBefore(weekStart) && !at.isAfter(current.toLocal())) {
        week.update(mark.accountId, (value) => value + 1, ifAbsent: () => 1);
      }
      if (!at.isBefore(todayStart) && !at.isAfter(current.toLocal())) {
        today.update(mark.accountId, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return {
      for (final id in total.keys)
        id: AttendanceCounts(
          total: total[id]!,
          week: week[id] ?? 0,
          today: today[id] ?? 0,
        ),
    };
  }
}
