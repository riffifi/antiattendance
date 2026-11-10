import 'package:flutter/foundation.dart';

import 'pulse_api.dart';
import 'server_api.dart';
import 'server_sessions.dart';

/// One frozen class/selection per camera session. Never retries lost mutations.
class ServerScanQueue extends ChangeNotifier {
  ServerScanQueue({
    required this.api,
    required List<Map<String, dynamic>> people,
    required this.lessonStart,
  }) : people = List.unmodifiable(
         people.map((p) => Map<String, dynamic>.unmodifiable(p)),
       );
  final AaServerApi api;
  final List<Map<String, dynamic>> people;
  final int lessonStart;
  final results = <String, Map<String, dynamic>>{};
  final _seen = <String>{};
  bool processing = false, paused = false, blocked = false, _disposed = false;
  Object? error;
  bool get canRetry =>
      !(error is SessionServerException &&
          [401, 403, 409].contains((error as SessionServerException).status));
  int get confirmed =>
      people.where((p) => results[p['id']]?['state'] == 'approved').length;
  int get remaining => people.length - confirmed;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> accept(String raw) async {
    if (_disposed || processing || paused || blocked || remaining == 0) return;
    final String token;
    try {
      token = attendanceTokenFromQr(raw);
    } on FormatException {
      return;
    }
    if (_seen.contains(token)) return;
    if (_seen.length >= 100) _seen.remove(_seen.first);
    _seen.add(token);
    final ids = people
        .where((p) => results[p['id']]?['state'] != 'approved')
        .map((p) => p['id'] as String)
        .toSet();
    processing = true;
    error = null;
    _notify();
    try {
      final rows = await api.mark(raw, ids, lessonStart: lessonStart);
      if (_disposed) return;
      final returned = <String>{};
      for (final result in rows) {
        final id = result['id'];
        if (id is String && ids.contains(id)) {
          results[id] = result;
          returned.add(id);
        }
      }
      // Missing results and upstream errors have an uncertain outcome. Require
      // an explicit retry instead of resubmitting on the next camera frame.
      blocked =
          returned.length != ids.length ||
          rows.any((r) => r['state'] == 'error');
      if (blocked) {
        error = const FormatException('Attendance result incomplete.');
      }
    } catch (e) {
      if (!_disposed) {
        error = e;
        blocked = true;
      }
    } finally {
      if (!_disposed) {
        processing = false;
        _notify();
      }
    }
  }

  void retry() {
    if (processing || _disposed || !canRetry) return;
    blocked = false;
    error = null;
    _seen.clear();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
