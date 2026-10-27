import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'haptics_test.dart' show Haptics, Audio;

void main() {
  testWidgets(
    'Colour plane and hue own horizontal and diagonal drags inside page switcher',
    (tester) async {
      var page = 0;
      Color colour = const Color(0xff39a6a0);
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, set) => BrockmannPageSwitcher(
                selected: page,
                pageCount: 3,
                onChanged: (v) => set(() => page = v),
                child: ListView(
                  children: [
                    BrockmannColorField(
                      label: 'colour',
                      value: colour,
                      onChanged: (v) => set(() => colour = v),
                    ),
                    const SizedBox(height: 600),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final plane = find.byKey(const ValueKey('brockmann-colour-plane'));
      final before = colour;
      final touch = await tester.startGesture(tester.getCenter(plane));
      await touch.moveBy(const Offset(140, 35));
      await tester.pump();
      expect(page, 0);
      expect(colour, isNot(before));
      await touch.up();
      await tester.pumpAndSettle();
      final hue = find.byType(BrockmannSlider).first;
      final track = find
          .descendant(of: hue, matching: find.byType(CustomPaint))
          .first;
      final oldHue = colour;
      await tester.drag(track, const Offset(-140, 0));
      await tester.pumpAndSettle();
      expect(page, 0);
      expect(colour, isNot(oldHue));
      // Ordinary whitespace remains a screen-navigation gesture.
      final blank = await tester.startGesture(const Offset(400, 560));
      await blank.moveBy(const Offset(-140, 0));
      await tester.pump();
      await blank.up();
      await tester.pumpAndSettle();
      expect(page, 1);
    },
  );
  testWidgets(
    'Dial arc remains interactive inside a vertical list and page switcher',
    (tester) async {
      var page = 0, value = .4;
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, set) => BrockmannPageSwitcher(
                selected: page,
                pageCount: 3,
                onChanged: (v) => set(() => page = v),
                child: ListView(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: BrockmannKnob(
                        label: 'tone',
                        value: value,
                        onChanged: (v) => set(() => value = v),
                      ),
                    ),
                    const SizedBox(height: 700),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final paint = find
          .descendant(
            of: find.byType(BrockmannKnob),
            matching: find.byType(CustomPaint),
          )
          .first;
      final centre = tester.getCenter(paint);
      final touch = await tester.startGesture(centre + const Offset(36, 0));
      await touch.moveTo(centre + const Offset(-20, 30));
      await tester.pump();
      await touch.up();
      await tester.pumpAndSettle();
      expect(page, 0);
      expect(value, greaterThan(.6));
    },
  );
  testWidgets('Handle hold has one tactile pickup, never repeated drag ticks', (
    tester,
  ) async {
    final haptics = Haptics();
    final feedback = BrockmannFeedbackController(
      backend: Audio(),
      hapticBackend: haptics,
    );
    addTearDown(feedback.dispose);
    var value = .5;
    await tester.pumpWidget(
      BrockmannApp(
        feedback: feedback,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StatefulBuilder(
              builder: (c, set) => BrockmannSlider(
                label: 'level',
                value: value,
                onChanged: (v) => set(() => value = v),
              ),
            ),
          ),
        ),
      ),
    );
    final paint = find
        .descendant(
          of: find.byType(BrockmannSlider),
          matching: find.byType(CustomPaint),
        )
        .first;
    final touch = await tester.startGesture(tester.getCenter(paint));
    await tester.pump(const Duration(milliseconds: 170));
    expect(haptics.gestures, [true]);
    await touch.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 250));
    expect(haptics.gestures, [true]);
    await touch.up();
    await tester.pumpAndSettle();
    await feedback.configure(haptics: BrockmannHapticMode.off);
    final muted = await tester.startGesture(
      tester.getTopLeft(paint) + Offset(12 + value * 296, 24),
    );
    await tester.pump(const Duration(milliseconds: 170));
    expect(haptics.gestures, [true]);
    await muted.up();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Both range handles own drags and get one pickup each', (
    tester,
  ) async {
    var page = 0;
    var values = const RangeValues(.2, .8);
    final haptics = Haptics();
    final feedback = BrockmannFeedbackController(
      backend: Audio(),
      hapticBackend: haptics,
    );
    addTearDown(feedback.dispose);
    await tester.pumpWidget(
      BrockmannApp(
        feedback: feedback,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 400,
            child: StatefulBuilder(
              builder: (c, set) => BrockmannPageSwitcher(
                selected: page,
                pageCount: 2,
                onChanged: (v) => set(() => page = v),
                child: Column(
                  children: [
                    BrockmannRangeSlider(
                      label: 'region',
                      values: values,
                      onChanged: (v) => set(() => values = v),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final range = find.byType(RangeSlider);
    final rect = tester.getRect(range);
    Offset handle(double value) =>
        Offset(rect.left + 24 + value * (rect.width - 48), rect.center.dy);
    final first = await tester.startGesture(handle(values.start));
    await tester.pump(const Duration(milliseconds: 170));
    expect(haptics.gestures, [true]);
    await first.moveBy(const Offset(70, 0));
    await tester.pump();
    await first.up();
    await tester.pumpAndSettle();
    expect(page, 0);
    expect(values.start, greaterThan(.2));
    expect(haptics.gestures, [true]);
    final second = await tester.startGesture(handle(values.end));
    await tester.pump(const Duration(milliseconds: 170));
    expect(haptics.gestures, [true, true]);
    await second.moveBy(const Offset(-35, 0));
    await tester.pump();
    await second.up();
    await tester.pumpAndSettle();
    expect(page, 0);
    expect(values.end, lessThan(.8));
    expect(haptics.gestures, [true, true]);
    await tester.pumpWidget(const SizedBox());
  });
}
