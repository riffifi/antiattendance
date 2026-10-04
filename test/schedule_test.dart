import 'package:antiattendance/campus_design.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

import 'dart:async';
import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/attendance_log.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/pulse_api.dart';
import 'package:antiattendance/schedule_api.dart';
import 'package:antiattendance/schedule_page.dart';
import 'package:material_ui/material_ui.dart';
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

class DelayedRefreshSchedule extends ScheduleApi {
  final refreshDone = Completer<List<ScheduleLesson>>();

  @override
  Future<List<ScheduleLesson>> lessonsForWeek(
    int groupId,
    DateTime weekStart, {
    bool refresh = false,
  }) async => refresh ? refreshDone.future : <ScheduleLesson>[];
}

void main() {
  DateTime todayAt(int hour, int minute) {
    final moscow = DateTime.now().toUtc().add(const Duration(hours: 3));
    return DateTime.utc(moscow.year, moscow.month, moscow.day, hour, minute);
  }

  testWidgets('schedule refresh spins until loading finishes', (tester) async {
    final api = DelayedRefreshSchedule();
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
            api: api,
            log: FakeLog([]),
            onScanLesson: (_, _) async {},
            onPasteLesson: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rotation = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is M3EIconButton && w.tooltip == 'Refresh',
      ),
      matching: find.byType(RotationTransition),
    );
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is M3EIconButton && w.tooltip == 'Refresh',
      ),
    );
    await tester.pump();
    final before = tester.widget<RotationTransition>(rotation).turns.value;
    expect(
      tester.widget<RotationTransition>(rotation).turns.isAnimating,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      tester.widget<RotationTransition>(rotation).turns.value,
      greaterThan(before),
    );
    api.refreshDone.complete([]);
    await tester.pumpAndSettle();
    expect(
      tester.widget<RotationTransition>(rotation).turns.isAnimating,
      isFalse,
    );
    expect(tester.widget<RotationTransition>(rotation).turns.value, 0);
    api.close();
  });

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
      start: todayAt(9, 0),
      end: todayAt(10, 30),
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
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is M3EIconButton && w.tooltip == 'Next week',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A free day'), findsOneWidget);
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    expect(find.text('Mathematics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasted QR approval is shown under the chosen lesson', (
    tester,
  ) async {
    final lesson = ScheduleLesson(
      key: '769:class-1:today',
      groupId: 769,
      start: todayAt(9, 0),
      end: todayAt(10, 30),
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
    await tester.tap(find.byIcon(Icons.calendar_today_outlined).last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Mathematics'), 150);
    await tester.tap(find.text('Mathematics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CampusTextField).last,
      'https://pulse.mirea.ru/lessons/visiting-logs/self-approve?token=abc',
    );
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(log.marks.single.lessonKey, lesson.key);
    expect(log.marks.single.pulseLessonId, 'pulse-42');
    expect(find.text('Anya'), findsOneWidget);
  });

  testWidgets('day schedule fits a narrow phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lesson = ScheduleLesson(
      key: 'lesson',
      groupId: 769,
      start: todayAt(9, 0),
      end: todayAt(10, 30),
      subject: 'A very long class title for a narrow screen',
      type: 'Lecture',
      location: 'Room 321',
      teachers: 'Teacher',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 568),
              textScaler: TextScaler.linear(1.3),
            ),
            child: SchedulePage(
              accounts: const [
                SavedAccount(
                  id: 'a',
                  label: 'Anya',
                  cookie: 'one',
                  groupId: 769,
                  groupName: 'A long university group name',
                ),
              ],
              api: FakeSchedule(lesson),
              log: FakeLog([]),
              onScanLesson: (_, _) async {},
              onPasteLesson: (_, _) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('A very long class title for a narrow screen'),
      120,
    );
    expect(
      find.text('A very long class title for a narrow screen'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
