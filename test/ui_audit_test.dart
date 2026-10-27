import 'dart:async';

import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/expressive.dart';
import 'package:antiattendance/group_picker_page.dart';
import 'package:antiattendance/schedule_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

class _PendingGroups extends ScheduleApi {
  final pending = Completer<List<ScheduleGroup>>();
  @override
  Future<List<ScheduleGroup>> searchGroups(String query) => pending.future;
}

void main() {
  testWidgets('long row actions leave readable space for the headline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: CampusListItem(
              headline: 'Alex Morgan',
              supportingText: 'Sign-in needed',
              trailing: CampusButton.text(
                onPressed: () {},
                child: const Text('Sign in again'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.text('Alex Morgan')).width, greaterThan(130));
    expect(
      tester.getRect(find.byType(CampusButton)).right,
      lessThanOrEqualTo(308),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long sheet stays scrollable above the keyboard and has an accessible close action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: const EdgeInsets.only(bottom: 280),
              textScaler: const TextScaler.linear(1.8),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => CampusButton.text(
                onPressed: () => showExpressiveSheet<void>(
                  context: context,
                  compact: true,
                  builder: (context) => Column(
                    children: [
                      for (var i = 0; i < 14; i++)
                        CampusListItem(headline: 'Option $i'),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final close = find.byTooltip('Close');
      expect(close, findsOneWidget);
      expect(tester.getRect(close).bottom, lessThanOrEqualTo(360));
      await tester.scrollUntilVisible(
        find.text('Option 13'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets(
    'clearing a pending group search clears its spinner and ignores its stale result',
    (tester) async {
      final api = _PendingGroups();
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: GroupPickerPage(api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Enter at least two characters and search.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'test');
      await tester.tap(find.byTooltip('Search'));
      await tester.pump();
      expect(find.byType(CampusProgress), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.byTooltip('Search'));
      await tester.pump();
      expect(find.byType(CampusProgress), findsNothing);
      api.pending.complete([const ScheduleGroup(id: 1, name: 'Old result')]);
      await tester.pumpAndSettle();
      expect(find.text('Old result'), findsNothing);
      expect(
        find.text('Enter at least two characters and search.'),
        findsOneWidget,
      );
    },
  );
}
