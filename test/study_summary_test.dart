import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/attendance_log.dart';
import 'package:antiattendance/schedule_api.dart';
import 'package:antiattendance/study_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScheduleLesson lesson(String key, int group, int start, int end) =>
      ScheduleLesson(
        key: key,
        groupId: group,
        start: DateTime.utc(2026, 10, 6, start),
        end: DateTime.utc(2026, 10, 6, end),
        subject: key,
        type: '',
        location: '',
        teachers: '',
      );
  final accounts = [
    const SavedAccount(id: 'a', label: 'Alice', cookie: 'one', groupId: 42),
    SavedAccount(
      id: 'b',
      label: 'Bob',
      cookie: 'two',
      groupId: 43,
      expiresAt: DateTime.utc(2026, 10, 6, 13),
    ),
    const SavedAccount(
      id: 'c',
      label: 'No group',
      cookie: 'three',
      sessionExpired: true,
    ),
  ];
  test('summary uses the actual last end across groups in Moscow time', () {
    final summaries = buildStudySummaries(
      accounts: accounts,
      lessons: [
        lesson('late', 43, 16, 18),
        lesson('early', 42, 9, 11),
        lesson('unrelated', 99, 19, 22),
      ],
      marks: [
        AttendanceMark(
          accountId: 'a',
          accountLabel: 'Alice',
          at: DateTime.utc(2026, 10, 6, 7),
          lessonKey: 'early',
        ),
      ],
      now: DateTime.utc(2026, 10, 6, 5),
    );
    expect(summaries, hasLength(1));
    expect(
      summaries.single['at'],
      DateTime.utc(2026, 10, 6, 15).millisecondsSinceEpoch,
    );
    final people = summaries.single['people'] as List<Map<String, Object?>>;
    expect(people[0]['counts'], '1/1');
    expect((people[0]['lines'] as List).single, contains('Confirmed'));
    expect(people[1]['counts'], '0/1');
    expect((people[1]['lines'] as List).single, contains('Not recorded'));
    expect(
      people[1]['sessionExpiresAt'],
      DateTime.utc(2026, 10, 6, 13).millisecondsSinceEpoch,
    );
    expect(people[2]['sessionExpired'], true);
    expect(
      (people[2]['lines'] as List).single,
      'Assign a group to include classes.',
    );
  });
  test('days without classes and past days do not get a notification', () {
    expect(
      buildStudySummaries(
        accounts: accounts,
        lessons: [],
        marks: [],
        now: DateTime.utc(2026, 10, 6),
      ),
      isEmpty,
    );
    expect(
      buildStudySummaries(
        accounts: accounts,
        lessons: [lesson('early', 42, 9, 11)],
        marks: [],
        now: DateTime.utc(2026, 10, 7),
      ),
      isEmpty,
    );
  });
  test('unlinked confirmations stay separate from scheduled classes', () {
    final summary = buildStudySummaries(
      accounts: accounts,
      lessons: [lesson('early', 42, 9, 11)],
      marks: [
        AttendanceMark(
          accountId: 'a',
          accountLabel: 'Alice',
          at: DateTime.utc(2026, 10, 6, 7),
        ),
      ],
      now: DateTime.utc(2026, 10, 6, 5),
      language: 'ru',
    ).single;
    final alice = (summary['people'] as List).first as Map;
    expect(alice['counts'], '0/1');
    expect(alice['lines'], contains('Другие подтверждения: 1'));
    expect(summary['title'], 'Итоги учебного дня');
  });
  test('day boundary uses Moscow even when the device UTC date differs', () {
    expect(moscowCivilTime(DateTime.utc(2026, 10, 5, 22)).day, 6);
    expect(
      moscowInstant(DateTime.utc(2026, 10, 6, 1)),
      DateTime.utc(2026, 10, 5, 22),
    );
  });
}
