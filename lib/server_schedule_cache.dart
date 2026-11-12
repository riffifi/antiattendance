import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedServerSchedule {
  const SavedServerSchedule(this.data, this.savedAt);
  final Map<String, dynamic> data;
  final DateTime savedAt;
}

/// Encrypted, bounded timetable metadata. Never stores attendance or credentials.
class ServerScheduleCache {
  ServerScheduleCache({FlutterSecureStorage? storage, DateTime Function()? now})
    : _storage = storage ?? const FlutterSecureStorage(),
      _now = now ?? DateTime.now;
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  static Future<void> _writes = Future.value();

  String _key(String scope) =>
      'schedule_cache_v1_${sha256.convert(utf8.encode(scope))}';
  String _week(int offset) {
    final moscow = _now().toUtc().add(const Duration(hours: 3));
    final date = DateTime.utc(moscow.year, moscow.month, moscow.day);
    return date
        .subtract(Duration(days: date.weekday - 1))
        .add(Duration(days: offset * 7))
        .toIso8601String()
        .substring(0, 10);
  }

  Future<Map<String, dynamic>> _read(String scope) async {
    final raw = await _storage
        .read(key: _key(scope))
        .timeout(const Duration(seconds: 1));
    if (raw == null || raw.length > 1000000) return {};
    final value = jsonDecode(raw);
    return value is Map<String, dynamic> ? value : {};
  }

  Future<SavedServerSchedule?> load(
    String scope,
    int week, {
    String? monday,
  }) async {
    try {
      final key = monday ?? _week(week);
      final row = (await _read(scope))[key];
      if (row is! Map || row['data'] is! Map<String, dynamic>) return null;
      final saved = DateTime.tryParse('${row['saved_at']}');
      if (saved == null ||
          saved.isAfter(_now().toUtc()) ||
          _now().toUtc().difference(saved) > const Duration(days: 14)) {
        return null;
      }
      final data = row['data'] as Map<String, dynamic>;
      if (data['days'] is! List) return null;
      return SavedServerSchedule(data, saved);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String scope,
    int week,
    Map<String, dynamic> data, {
    String? monday,
  }) {
    final weekKey = monday ?? _week(week);
    if (data['days'] is! List || data['schedule_error'] != null) {
      return Future.value();
    }
    final safe = <String, dynamic>{
      for (final key in ['group_name', 'group_id', 'monday'])
        if (data.containsKey(key)) key: data[key],
      'days': [
        for (final day in (data['days'] as List).whereType<Map>().take(7))
          {
            for (final key in ['date'])
              if (day.containsKey(key)) key: day[key],
            'lessons': [
              for (final lesson
                  in (day['lessons'] is List
                          ? day['lessons'] as List
                          : const [])
                      .whereType<Map>()
                      .take(30))
                {
                  for (final key in [
                    'start',
                    'end',
                    'subject',
                    'type',
                    'teacher',
                    'location',
                  ])
                    if (lesson.containsKey(key)) key: lesson[key],
                },
            ],
          },
      ],
    };
    final task = _writes.then((_) async {
      Map<String, dynamic> entries;
      try {
        entries = await _read(scope);
      } catch (_) {
        entries = {};
      }
      entries.removeWhere(
        (key, value) =>
            value is! Map ||
            value['data'] is! Map ||
            value['saved_at'] is! String ||
            DateTime.tryParse('${value['saved_at']}') == null,
      );
      entries[weekKey] = {
        'saved_at': _now().toUtc().toIso8601String(),
        'data': safe,
      };
      final keys = entries.keys.toList()
        ..sort(
          (a, b) =>
              DateTime.parse('${entries[b]['saved_at']}')
                  .compareTo(DateTime.parse('${entries[a]['saved_at']}')),
        );
      final bounded = {for (final key in keys.take(5)) key: entries[key]};
      final encoded = jsonEncode(bounded);
      if (encoded.length <= 1000000) {
        await _storage
            .write(key: _key(scope), value: encoded)
            .timeout(const Duration(seconds: 1));
        await _retainScope(_key(scope));
      }
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> _retainScope(String key) async {
    const index = 'schedule_cache_scopes_v1';
    List<String> keys = [];
    try {
      final raw = await _storage
          .read(key: index)
          .timeout(const Duration(seconds: 1));
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is List) {
        keys = decoded
            .whereType<String>()
            .where(
              (k) => RegExp(r'^schedule_cache_v1_[a-f0-9]{64}$').hasMatch(k),
            )
            .toSet()
            .toList();
      }
    } catch (_) {}
    keys.remove(key);
    keys.add(key);
    while (keys.length > 8) {
      await _storage
          .delete(key: keys.removeAt(0))
          .timeout(const Duration(seconds: 1));
    }
    await _storage
        .write(key: index, value: jsonEncode(keys))
        .timeout(const Duration(seconds: 1));
  }

  static bool _isCacheKey(String key) =>
      RegExp(r'^schedule_cache_v1_[a-f0-9]{64}$').hasMatch(key);

  Future<int> countWeeks() async {
    await _writes;
    final values = await _storage.readAll().timeout(const Duration(seconds: 2));
    var count = 0;
    for (final entry in values.entries.where((e) => _isCacheKey(e.key))) {
      try {
        final decoded = jsonDecode(entry.value);
        if (decoded is Map) count += decoded.length;
      } catch (_) {}
    }
    return count;
  }

  /// Remove only timetable keys, including orphaned copies after a bad index.
  /// Serializing with saves prevents a queued write from restoring old copies.
  Future<void> clearAll() {
    final task = _writes.then((_) async {
      final values = await _storage.readAll().timeout(
        const Duration(seconds: 2),
      );
      for (final key
          in values.keys.where(_isCacheKey).toList(growable: false)) {
        await _storage.delete(key: key).timeout(const Duration(seconds: 1));
      }
      await _storage
          .delete(key: 'schedule_cache_scopes_v1')
          .timeout(const Duration(seconds: 1));
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> clear(String scope) async {
    await _writes;
    await _storage.delete(key: _key(scope)).timeout(const Duration(seconds: 1));
  }
}
