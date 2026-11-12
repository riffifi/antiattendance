import 'dart:async';

import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/schedule_storage_page.dart';
import 'package:antiattendance/server_schedule_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCache extends ServerScheduleCache {
  int weeks = 3, calls = 0;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<int> countWeeks() async => weeks;
  @override
  Future<void> clearAll() async {
    calls++;
    if (fail) throw StateError('storage unavailable');
    if (pending != null) await pending!.future;
    weeks = 0;
  }
}

void main() {
  for (final mode in AppThemeMode.values) {
    testWidgets(
      'offline controls stay reachable at 320dp and double text: $mode',
      (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(mode),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: ScheduleStoragePage(cache: FakeCache()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Clear saved schedules'),
          120,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear saved schedules'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Saved weeks: 0'),
          -160,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Saved weeks: 0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('clear is single-flight and reports the new stored count', (
    tester,
  ) async {
    final cache = FakeCache()..pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppThemeMode.dark),
        home: ScheduleStoragePage(cache: cache),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved weeks: 3'), findsOneWidget);
    await tester.tap(find.text('Clear saved schedules'));
    await tester.pump();
    expect(
      tester
          .widget<CampusButton>(
            find.widgetWithText(CampusButton, 'Clear saved schedules'),
          )
          .onPressed,
      isNull,
    );
    cache.pending!.complete();
    await tester.pumpAndSettle();
    expect(cache.calls, 1);
    expect(find.text('Saved weeks: 0'), findsOneWidget);
    expect(
      find.textContaining('Accounts, passes and settings stay'),
      findsOneWidget,
    );
  });
  testWidgets(
    'failed storage clear leaves an actionable retry and keeps the prior count',
    (tester) async {
      final cache = FakeCache()..fail = true;
      await tester.pumpWidget(
        MaterialApp(home: ScheduleStoragePage(cache: cache)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear saved schedules'));
      await tester.pumpAndSettle();
      expect(find.text('Saved weeks: 3'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.textContaining('Could not update saved schedules'),
        findsOneWidget,
      );
      cache.fail = false;
      await tester.tap(find.text('Clear saved schedules'));
      await tester.pumpAndSettle();
      expect(find.text('Saved weeks: 0'), findsOneWidget);
    },
  );
}
