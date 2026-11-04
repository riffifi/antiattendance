import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/screen_navigation.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone pivot and tablet list retain an unfinished form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, update) => ScreenNavigation(
            selectedIndex: selected,
            onSelected: (i) => update(() => selected = i),
            child: const BrockmannPage(
              child: BrockmannTextField(label: 'Draft'),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'Keep this draft');
    final state = tester.state(find.byType(TextFormField));
    final destination = find.descendant(
      of: find.byType(BrockmannPivot),
      matching: find.text('schedule'),
    );
    await tester.ensureVisible(destination);
    await tester.tap(destination);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.state(find.byType(TextFormField)), same(state));
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(find.byType(BrockmannNavigationList), findsOneWidget);
    expect(tester.state(find.byType(TextFormField)), same(state));
    expect(find.text('Keep this draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'diagnostics require five distinct header pulls and ignore content drags',
    (tester) async {
      var reveals = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ScreenNavigation(
            selectedIndex: 0,
            onSelected: (_) {},
            onRevealDebug: () => reveals++,
            child: const ColoredBox(
              color: Colors.white,
              child: SizedBox.expand(key: ValueKey('content')),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.drag(
          find.byKey(const ValueKey('content')),
          const Offset(0, 120),
        );
      }
      expect(reveals, 0);
      final header = find.byKey(const ValueKey('app-diagnostics-gesture'));
      for (var i = 0; i < 4; i++) {
        await tester.drag(header, const Offset(0, 120));
        await tester.pumpAndSettle();
        expect(reveals, 0);
      }
      await tester.drag(header, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(reveals, 1);
    },
  );
}
