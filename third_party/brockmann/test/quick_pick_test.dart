import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Hold uses the regular anchored geometry, reveal and closing label handoff',
    (tester) async {
      var selected = 1;
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (c, set) => BrockmannPicker(
                    label: 'choice',
                    options: const ['one', 'two', 'a longer third option'],
                    selected: selected,
                    presentation: BrockmannPickerPresentation.anchored,
                    onChanged: (v) => set(() => selected = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final field = find.byType(BrockmannPicker);
      final panel = find.byKey(const ValueKey('brockmann-picker-panel'));
      Finder option(String text) =>
          find.descendant(of: find.byType(ListView), matching: find.text(text));
      await tester.tap(field);
      await tester.pumpAndSettle();
      final regularPanel = tester.getRect(panel);
      final regularText = tester.getRect(option('two'));
      final regularStyle = tester.widget<Text>(option('two')).style;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(field));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      final collapsed = tester.getRect(panel);
      expect(collapsed.height, lessThan(regularPanel.height));
      await tester.pump(const Duration(milliseconds: 80));
      final revealing = tester.getRect(panel);
      expect(revealing.height, greaterThan(collapsed.height));
      expect(revealing.height, lessThan(regularPanel.height));
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.getRect(panel), regularPanel);
      expect(tester.getRect(option('two')), regularText);
      expect(tester.widget<Text>(option('two')).style, regularStyle);
      await gesture.moveTo(tester.getCenter(option('a longer third option')));
      await tester.pump(const Duration(milliseconds: 160));
      final source = tester.getTopLeft(option('a longer third option'));
      await gesture.up();
      await tester.pump();
      expect(selected, 2);
      final carried = find.byKey(const ValueKey('brockmann-picker-carry'));
      expect(carried, findsOneWidget);
      expect(tester.getTopLeft(carried), source);
      final destination = tester.getTopLeft(
        find.descendant(
          of: field,
          matching: find.text('a longer third option'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        (tester.getTopLeft(carried) - destination).distance,
        lessThan((source - destination).distance),
      );
      await tester.pumpAndSettle();
      expect(carried, findsNothing);
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Hold, drag and release commits once; releasing outside cancels',
    (tester) async {
      var value = 0;
      var commits = 0;
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: StatefulBuilder(
                  builder: (c, set) => BrockmannPicker(
                    label: 'choice',
                    options: const ['one', 'two', 'three'],
                    selected: value,
                    presentation: BrockmannPickerPresentation.anchored,
                    onChanged: (v) => set(() {
                      value = v;
                      commits++;
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      var gesture = await tester.startGesture(
        tester.getCenter(find.byType(BrockmannPicker)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      final option = find.descendant(
        of: find.byType(ListView),
        matching: find.text('two'),
      );
      expect(option, findsOneWidget);
      await gesture.moveTo(tester.getCenter(option));
      await tester.pump(const Duration(milliseconds: 100));
      expect(commits, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(value, 1);
      expect(commits, 1);
      gesture = await tester.startGesture(
        tester.getCenter(find.byType(BrockmannPicker)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await gesture.moveTo(const Offset(2, 2));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, 1);
      gesture = await tester.startGesture(
        tester.getCenter(find.byType(BrockmannPicker)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, 1);
      expect(find.byType(ListView), findsNothing);
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: BrockmannPicker(
                  label: 'long choice',
                  options: List.generate(40, (i) => 'option $i'),
                  selected: 0,
                  presentation: BrockmannPickerPresentation.anchored,
                  onChanged: (v) {
                    value = v;
                    commits++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      gesture = await tester.startGesture(
        tester.getCenter(find.byType(BrockmannPicker)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      final panel = tester.getRect(find.byType(ListView));
      await gesture.moveTo(Offset(panel.center.dx, panel.bottom - 10));
      for (var frame = 0; frame < 100; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(commits, 1);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(commits, 2);
      expect(value, greaterThan(8));
      expect(tester.takeException(), isNull);
    },
  );
}
