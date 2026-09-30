import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/attendance_log.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/pulse_api.dart';
import 'package:antiattendance/schedule_api.dart';
import 'package:antiattendance/schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const calendar = '''BEGIN:VCALENDAR
BEGIN:VEVENT
UID:class-1
DTSTART;TZID=Europe/Moscow:20260914T090000
DTEND;TZID=Europe/Moscow:20260914T103000
RRULE:FREQ=WEEKLY;INTERVAL=2;UNTIL=20261231T000000
EXDATE;TZID=Europe/Moscow:20260928T090000
X-META-DISCIPLINE:Mathematics
X-META-LESSON_TYPE:Lecture
LOCATION:Room 1
END:VEVENT
END:VCALENDAR''';

class FakeLog extends AttendanceLogStore {
  FakeLog(this.marks);
  final List<AttendanceMark> marks;
  @override
  Future<List<AttendanceMark>> load() async => marks;
  @override
  Future<void> add(AttendanceMark mark) async => marks.add(mark);
}

class FakeAccounts extends AccountStore {
  @override
  Future<List<SavedAccount>> load() async => const [
    SavedAccount(
      id: 'a',
      label: 'Anya',
      cookie: 'one',
      groupId: 769,
      groupName: 'ИНБО-10-23',
    ),
  ];
}

class FakePulse extends PulseApi {
  @override
  Future<ApprovalResult> approve(String token, String cookie) async =>
      const ApprovalResult(
        ApprovalState.approved,
        'Присутствие подтверждено',
        lessonId: 'pulse-42',
      );
}

class FakeSchedule extends ScheduleApi {
  FakeSchedule(this.lesson);
  final ScheduleLesson lesson;
  @override
  Future<List<ScheduleLesson>> lessonsForWeek(
    int groupId,
    DateTime weekStart, {
    bool refresh = false,
  }) async => [lesson];
}

void main() {
  test('searches only groups and reads the public calendar endpoint', () async {
    final paths = <String>[];
    final api = ScheduleApi(
      client: MockClient((request) async {
        paths.add(request.url.toString());
        if (request.url.path.endsWith('/search')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 769, 'targetTitle': 'ИНБО-10-23', 'scheduleTarget': 1},
                {'id': 3, 'targetTitle': 'A building', 'scheduleTarget': 2},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(calendar, 200);
      }),
    );
    final groups = await api.searchGroups('ИНБО');
    expect(groups.map((g) => g.name), ['ИНБО-10-23']);
    final lessons = await api.lessonsForWeek(769, DateTime.utc(2026, 9, 14));
    expect(lessons.single.start, DateTime.utc(2026, 9, 14, 9));
    expect(lessons.single.subject, 'Mathematics');
    expect(paths.singleWhere((p) => p.contains('/search')), contains('match='));
    expect(paths.last, contains('/ical/Group/769'));
    api.close();
  });

  test('alternating week and exception dates are respected', () {
    expect(
      parseGroupCalendar(calendar, 769, DateTime.utc(2026, 9, 14)),
      hasLength(1),
    );
    expect(
      parseGroupCalendar(calendar, 769, DateTime.utc(2026, 9, 21)),
      isEmpty,
    );
    expect(
      parseGroupCalendar(calendar, 769, DateTime.utc(2026, 9, 28)),
      isEmpty,
    );
    expect(
      parseGroupCalendar(calendar, 769, DateTime.utc(2026, 10, 12)),
      hasLength(1),
    );
  });

  testWidgets('shows only confirmed names for the selected class', (
    tester,
  ) async {
    final lesson = ScheduleLesson(
      key: '769:class-1:today',
      groupId: 769,
      start: DateTime.utc(2026, 9, 30, 9),
      end: DateTime.utc(2026, 9, 30, 10, 30),
      subject: 'Mathematics',
      type: 'Lecture',
      location: 'Room 1',
      teachers: '',
    );
    final log = FakeLog([
      AttendanceMark(
        accountId: 'a',
        accountLabel: 'Anya',
        at: DateTime.now(),
        groupId: 769,
        lessonKey: lesson.key,
      ),
      AttendanceMark(
        accountId: 'b',
        accountLabel: 'Boris',
        at: DateTime.now(),
        groupId: 769,
        lessonKey: 'other-class',
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePage(
            accounts: const [
              SavedAccount(
                id: 'a',
                label: 'Anya',
                cookie: 'one',
                groupId: 769,
                groupName: 'ИНБО-10-23',
              ),
            ],
            api: FakeSchedule(lesson),
            log: log,
            onScanLesson: (_, _) async {},
            onPasteLesson: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Anya'), findsOneWidget);
    expect(find.text('Boris'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasted QR approval is shown under the chosen lesson', (
    tester,
  ) async {
    final lesson = ScheduleLesson(
      key: '769:class-1:today',
      groupId: 769,
      start: DateTime.utc(2026, 9, 30, 9),
      end: DateTime.utc(2026, 9, 30, 10, 30),
      subject: 'Mathematics',
      type: '',
      location: '',
      teachers: '',
    );
    final log = FakeLog([]);
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          store: FakeAccounts(),
          api: FakePulse(),
          scheduleApi: FakeSchedule(lesson),
          logStore: log,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'https://pulse.mirea.ru/lessons/visiting-logs/self-approve?token=abc',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(log.marks.single.lessonKey, lesson.key);
    expect(log.marks.single.pulseLessonId, 'pulse-42');
    expect(find.text('Anya'), findsOneWidget);
  });
}
