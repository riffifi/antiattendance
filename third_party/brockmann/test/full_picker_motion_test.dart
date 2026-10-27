import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder row(String text) =>
    find.descendant(of: find.byType(ListView), matching: find.text(text));
double rowOpacity(WidgetTester tester, String text) => tester
    .widget<Opacity>(
      find.ancestor(
        of: row(text),
        matching: find.byWidgetPredicate(
          (w) => w is Opacity && w.child is Transform,
        ),
      ),
    )
    .opacity;
Future<void> mount(WidgetTester tester, {int selected = 0, int count = 4}) =>
    tester.pumpWidget(
      BrockmannApp(
        home: Scaffold(
          body: BrockmannPicker(
            label: 'destination',
            options: List.generate(count, (i) => 'option $i'),
            selected: selected,
            presentation: BrockmannPickerPresentation.fullPage,
            onChanged: (_) {},
          ),
        ),
      ),
    );
void main() {
  testWidgets(
    'Full-page reveal is gradual and early closing preserves row position and opacity',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byType(BrockmannPicker));
      await tester.pump();
      await tester.pump();
      final fade = find.byKey(const ValueKey('brockmann-full-picker-fade'));
      expect(tester.widget<Opacity>(fade).opacity, 0);
      await tester.pump(const Duration(milliseconds: 80));
      final alpha = tester.widget<Opacity>(fade).opacity;
      expect(alpha, inExclusiveRange(0, 1));
      expect(rowOpacity(tester, 'option 0'), inExclusiveRange(0, 1));
      expect(
        rowOpacity(tester, 'option 1'),
        lessThan(rowOpacity(tester, 'option 0')),
      );
      final position = tester.getTopLeft(row('option 1'));
      final rowAlpha = rowOpacity(tester, 'option 1');
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(tester.widget<Opacity>(fade).opacity, closeTo(alpha, .00001));
      expect(tester.getTopLeft(row('option 1')), position);
      expect(rowOpacity(tester, 'option 1'), closeTo(rowAlpha, .00001));
      await tester.pump(const Duration(milliseconds: 130));
      expect(tester.widget<Opacity>(fade).opacity, inExclusiveRange(0, alpha));
      expect(tester.getTopLeft(row('option 1')).dx, greaterThan(position.dx));
      expect(rowOpacity(tester, 'option 1'), closeTo(rowAlpha, .00001));
      await tester.pumpAndSettle();
      expect(fade, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'A deep selection starts feathering immediately in the visible viewport',
    (tester) async {
      await mount(tester, selected: 30, count: 40);
      await tester.tap(find.byType(BrockmannPicker));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rowOpacity(tester, 'option 30'), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(rowOpacity(tester, 'option 30'), 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
