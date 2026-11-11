import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, {bool reduced = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppThemeMode.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: const Scaffold(
          body: CampusDisclosure(title: 'Details', children: [Text('Content')]),
        ),
      ),
    );
  }

  final stroke = find.byKey(const ValueKey('disclosure-vertical-stroke'));

  testWidgets(
    'disclosure stroke smoothly opens and closes without changing its target size',
    (tester) async {
      await show(tester);
      final closed = tester.getSize(stroke).height;
      final target = tester.getSize(find.byType(CampusDisclosure));
      await tester.tap(find.text('Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getSize(stroke).height, inExclusiveRange(0, closed));
      await tester.pumpAndSettle();
      expect(tester.getSize(stroke).height, 0);
      expect(find.text('Content'), findsOneWidget);
      await tester.tap(find.text('Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getSize(stroke).height, inExclusiveRange(0, closed));
      await tester.pumpAndSettle();
      expect(tester.getSize(stroke).height, closed);
      expect(tester.getSize(find.byType(CampusDisclosure)), target);
    },
  );

  testWidgets('rapid disclosure reversal continues from its current position', (
    tester,
  ) async {
    await show(tester);
    final closed = tester.getSize(stroke).height;
    await tester.tap(find.text('Details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midway = tester.getSize(stroke).height;
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(tester.getSize(stroke).height, closeTo(midway, .01));
    await tester.pumpAndSettle();
    expect(tester.getSize(stroke).height, closed);
    expect(find.text('Content'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion snaps the indicator to its new state', (
    tester,
  ) async {
    await show(tester, reduced: true);
    final closed = tester.getSize(stroke).height;
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(tester.getSize(stroke).height, 0);
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(tester.getSize(stroke).height, closed);
  });
}
