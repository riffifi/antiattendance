import 'package:antiattendance/app_theme.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget shell(Widget child, {bool reduced = false}) => MaterialApp(
    theme: AppTheme.build(AppThemeMode.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'compact switch stays in place while its label changes; reduced: $reduced',
      (tester) async {
        var value = false;
        await tester.pumpWidget(
          shell(
            StatefulBuilder(
              builder: (context, update) => BrockmannSwitch(
                label: 'Enabled',
                compact: true,
                sound: false,
                value: value,
                onLabel: 'On',
                offLabel: 'Disabled',
                onChanged: (next) => update(() => value = next),
              ),
            ),
            reduced: reduced,
          ),
        );
        final track = find
            .descendant(
              of: find.byType(BrockmannSwitch),
              matching: find.byType(CustomPaint),
            )
            .last;
        final before = tester.getRect(track);
        await tester.tap(find.byType(BrockmannSwitch));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        expect(value, isTrue);
        expect(tester.getRect(track), before);
        await tester.pumpAndSettle();
        expect(tester.getRect(track), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'navigation chevrons acknowledge a press without moving the row',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        shell(
          BrockmannListItem(
            label: 'Settings',
            chevron: true,
            onPressed: () => calls++,
          ),
        ),
      );
      final row = find.byType(BrockmannListItem);
      final glyph = find.byWidgetPredicate(
        (w) => w is BrockmannGlyph && w.icon == BrockmannIcon.caretRight,
      );
      final original = tester.getCenter(glyph);
      final bounds = tester.getRect(row);
      final press = await tester.startGesture(tester.getCenter(row));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.getCenter(glyph).dx, greaterThan(original.dx));
      expect(tester.getRect(row), bounds);
      expect(calls, 0);
      await press.up();
      expect(calls, 1);
      await tester.pumpAndSettle();
      expect(tester.getCenter(glyph).dx, closeTo(original.dx, .01));
    },
  );

  testWidgets('tab labels interpolate without changing the hit area', (
    tester,
  ) async {
    var value = 0;
    await tester.pumpWidget(
      shell(
        StatefulBuilder(
          builder: (context, update) => BrockmannSegmentedControl<int>(
            options: const [0, 1],
            value: value,
            labelFor: (v) => v == 0 ? 'One' : 'Two',
            onChanged: (next) => update(() => value = next),
          ),
        ),
      ),
    );
    final label = find.text('Two');
    final initial = tester.widget<Text>(label).style!.color!;
    final bounds = tester.getRect(label);
    await tester.tap(label);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final intermediate = tester.widget<Text>(label).style!.color!;
    expect(value, 1);
    expect(intermediate, isNot(initial));
    expect(tester.getRect(label), bounds);
    await tester.pumpAndSettle();
    final finalColor = tester.widget<Text>(label).style!.color!;
    expect(finalColor, isNot(initial));
    expect(intermediate, isNot(finalColor));
  });
}
