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
  test('server notification uses the same group-aware counts as Today', () {
    final fetchedAt = DateTime.utc(2026, 11, 12, 12);
    final summary = buildServerStudySummary({
      'date': '12.11.2026',
      'people': [
        {'id': 'a', 'label': 'Alice', 'group_id': 1, 'session': 'valid'},
        {'id': 'b', 'label': 'Bob', 'group_id': 2, 'session': 'expired'},
      ],
      'lessons': [
        {
          'start': '09:00',
          'end': '10:30',
          'subject': 'Algebra',
          'groups': [
            {'id': 1},
          ],
          'marks': {
            'a': {'state': 'approved', 'message': 'Присутствие подтверждено'},
          },
        },
        {
          'start': '11:00',
          'end': '12:30',
          'subject': 'Physics',
          'groups': [
            {'id': 2},
          ],
        },
      ],
    }, fetchedAt: fetchedAt).single;
    final people = summary['people'] as List;
    expect(people[0]['counts'], '1/1');
    expect(people[0]['lines'], ['09:00 Algebra · Confirmed']);
    expect(people[1]['counts'], '0/1');
    expect(people[1]['lines'], ['11:00 Physics · —']);
    expect(people[1]['sessionExpired'], isTrue);
    expect(summary['updatedAt'], fetchedAt.millisecondsSinceEpoch);
    expect(
      summary['at'],
      DateTime.utc(2026, 11, 12, 9, 30).millisecondsSinceEpoch,
    );
  });

  test(
    'invalid server dates and class times cannot schedule a different day',
    () {
      for (final date in ['31.02.2026', '00.11.2026', 'not-a-date']) {
        expect(
          () => buildServerStudySummary({
            'date': date,
            'lessons': [
              {'end': '18:00'},
            ],
          }),
          throwsFormatException,
        );
      }
      for (final end in ['25:00', '18:60', 'not-a-time']) {
        expect(
          () => buildServerStudySummary({
            'date': '12.11.2026',
            'lessons': [
              {'end': end},
            ],
          }),
          throwsFormatException,
        );
      }
    },
  );

  test('day boundary uses Moscow even when the device UTC date differs', () {
    expect(moscowCivilTime(DateTime.utc(2026, 10, 5, 22)).day, 6);
    expect(
      moscowInstant(DateTime.utc(2026, 10, 6, 1)),
      DateTime.utc(2026, 10, 5, 22),
    );
  });
}
