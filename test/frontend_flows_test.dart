import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/frontend/attendance_page.dart';
import 'package:antiattendance/frontend/schedule_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {double scale = 1}) => MaterialApp(
  theme: AppTheme.light,
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'select all targets the searched group without changing hidden accounts',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final accounts = [
        for (var i = 0; i < 7; i++)
          SavedAccount(
            id: '$i',
            label: 'Person $i',
            cookie: 'test',
            groupId: i == 6 ? 43 : 42,
          ),
      ];
      Set<String>? changed;
      await tester.pumpWidget(
        app(
          AttendancePage(
            accounts: accounts,
            selected: {'0', '6'},
            groupId: 42,
            counts: null,
            results: {},
            errors: {},
            sessionChecks: {},
            checkingSessions: {},
            busy: false,
            submitting: false,
            legacyMode: true,
            onRefresh: () async {},
            onAdd: () {},
            onReceive: () {},
            onManage: (_) {},
            onGroupChanged: (_) {},
            onToggle: (_) {},
            onToggleAll: (ids) => changed = ids,
            onCheckSession: (_) {},
            onReauth: (_) {},
            onRename: (_) {},
            onGroup: (_) {},
            onRemove: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Person 1');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Select all'));
      await tester.tap(find.text('Select all'));
      expect(changed, {'1'});
      expect(find.text('Person 6'), findsNothing);
      expect(find.text('Person 0'), findsNothing);
      expect(find.byKey(const ValueKey('1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar reaches every weekday at 320dp and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DateTime? selected;
    final monday = DateTime.utc(2026, 11, 2);
    await tester.pumpWidget(
      app(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ScheduleCalendar(
              day: monday,
              today: monday,
              groups: {42: 'Group A'},
              groupId: 42,
              lessonDays: {monday},
              loading: false,
              onDayChanged: (date) => selected = date,
              onGroupChanged: (_) {},
              onMaps: () {},
              onRefresh: () {},
            ),
          ),
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    final sunday = find.text('8');
    await tester.ensureVisible(sunday);
    await tester.pumpAndSettle();
    await tester.tap(sunday);
    expect(selected, DateTime.utc(2026, 11, 8));
    expect(tester.takeException(), isNull);
  });
}
