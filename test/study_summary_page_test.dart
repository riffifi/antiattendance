import 'dart:convert';

import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/study_summary.dart';
import 'package:antiattendance/study_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'malformed saved data can be retried without crashing the screen',
    (tester) async {
      var valid = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            studySummaryChannel,
            (call) async => jsonEncode(
              valid
                  ? {
                      'id': '2026-11-12',
                      'at': 1794480000000,
                      'updatedAt': 1794480000000,
                      'people': [
                        {
                          'name': 'Alex',
                          'counts': '1/1',
                          'lines': ['09:00 Algebra · Confirmed'],
                        },
                      ],
                    }
                  : {'people': 'invalid'},
            ),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(studySummaryChannel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(AppThemeMode.dark),
          home: const StudySummaryPage(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load the summary.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      valid = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.textContaining('Results saved at'), findsOneWidget);
      expect(find.text('Could not load the summary.'), findsNothing);
    },
  );
}
