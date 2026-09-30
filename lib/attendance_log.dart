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
          item.lessonKey == mark.lessonKey &&
          item.lessonKey != null,
    )) {
      return;
    }
    marks.add(mark);
    final cutoff = DateTime.now().subtract(const Duration(days: 120));
    marks.removeWhere((item) => item.at.isBefore(cutoff));
    await _storage.write(key: _key, value: jsonEncode(marks));
  }
}
