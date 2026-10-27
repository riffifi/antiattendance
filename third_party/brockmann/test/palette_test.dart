import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Palette selection commits once and retains a semantic check', (
    tester,
  ) async {
    var value = 0, commits = 0;
    await tester.pumpWidget(
      BrockmannApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) => BrockmannColorPicker(
              label: 'palette',
              schemes: brockmannPalette(),
              selected: value,
              onChanged: (v) => set(() {
                value = v;
                commits++;
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('rose #DF6679'));
    await tester.pumpAndSettle();
    expect(value, 3);
    expect(commits, 1);
    await tester.tap(find.bySemanticsLabel('rose #DF6679'));
    await tester.pumpAndSettle();
    expect(commits, 1);
    expect(find.byType(BrockmannGlyph), findsOneWidget);
    final tile = tester.getSize(
      find.byKey(const ValueKey('brockmann-colour-tile-3')),
    );
    expect(tile.width, tile.height);
  });
  testWidgets(
    'Colour field touches change saturation and brightness immediately',
    (tester) async {
      Color value = const Color(0xff00ff00);
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (c, set) => BrockmannColorField(
                  label: 'colour',
                  value: value,
                  onChanged: (v) => set(() => value = v),
                ),
              ),
            ),
          ),
        ),
      );
      final plane = find.byKey(const ValueKey('brockmann-colour-plane'));
      final rect = tester.getRect(plane);
      await tester.tapAt(rect.center);
      await tester.pump();
      final hsv = HSVColor.fromColor(value);
      expect(hsv.saturation, closeTo(.5, .03));
      expect(hsv.value, closeTo(.5, .03));
      expect(tester.takeException(), isNull);
    },
  );
}
