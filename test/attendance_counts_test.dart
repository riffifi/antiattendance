import 'package:antiattendance/attendance_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'counts distinct approved lessons by local day and Monday-based week',
    () {
      final now = DateTime(2026, 10, 1, 12);
      AttendanceMark mark(String id, DateTime at, String lesson) =>
          AttendanceMark(
            accountId: id,
            accountLabel: id,
            at: at,
            pulseLessonId: lesson,
          );
      final counts = AttendanceCounts.fromMarks([
        mark('a', DateTime(2026, 9, 27, 23), 'previous-week'),
        mark('a', DateTime(2026, 9, 28, 0), 'this-week'),
        mark('a', DateTime(2026, 10, 1, 9), 'today'),
        mark('a', DateTime(2026, 10, 1, 10), 'today'),
        mark('b', DateTime(2026, 10, 1, 8), 'other-account'),
      ], now: now);

      expect(counts['a']?.total, 3);
      expect(counts['a']?.week, 2);
      expect(counts['a']?.today, 1);
      expect(counts['b']?.total, 1);
      expect(counts['b']?.week, 1);
      expect(counts['b']?.today, 1);
    },
  );
}
