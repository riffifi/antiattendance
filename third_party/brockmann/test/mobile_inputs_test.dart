import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Knob follows arc movement and supports centre vertical drag', (
    tester,
  ) async {
    var value = .4;
    await tester.pumpWidget(
      BrockmannApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) => Align(
              alignment: Alignment.topLeft,
              child: BrockmannKnob(
                label: 'tone',
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
          of: find.byType(BrockmannKnob),
          matching: find.byType(CustomPaint),
        )
        .first;
    final centre = tester.getCenter(paint);
    final gesture = await tester.startGesture(centre + const Offset(36, 0));
    await gesture.moveTo(centre + const Offset(0, 36));
    await tester.pump();
    expect(value, greaterThan(.65));
    await gesture.up();
    await tester.pumpAndSettle();
    final before = value;
    final fine = await tester.startGesture(centre);
    await fine.moveBy(const Offset(0, -20));
    await tester.pump();
    expect(value, greaterThan(before));
    await fine.up();
    await tester.pumpAndSettle();
  });
  testWidgets('Slider grabs without jumping and follows small deltas', (
    tester,
  ) async {
    var value = .5;
    await tester.pumpWidget(
      BrockmannApp(
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
    final centre = tester.getCenter(paint);
    final gesture = await tester.startGesture(centre + const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 120));
    expect(value, closeTo(.5, .001));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(value, closeTo(.5 + 30 / 296, .01));
    await gesture.up();
    await tester.pumpAndSettle();
  });
  testWidgets('Vertical meter retains its 4 dp width in a stretched column', (
    tester,
  ) async {
    await tester.pumpWidget(
      const BrockmannApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrockmannMeter(label: 'meter', db: -12, axis: Axis.vertical),
            ],
          ),
        ),
      ),
    );
    final paint = find.descendant(
      of: find.byType(BrockmannMeter),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(paint).width, 4);
  });
  testWidgets('Every Phosphor icon has both packaged weights', (tester) async {
    for (final icon in BrockmannIcon.values) {
      expect(
        (await rootBundle.load(
          'packages/brockmann/assets/icons/${icon.file}.svg',
        )).lengthInBytes,
        greaterThan(0),
      );
      expect(
        (await rootBundle.load(
          'packages/brockmann/assets/icons/${icon.file}-bold.svg',
        )).lengthInBytes,
        greaterThan(0),
      );
    }
  });
  testWidgets('All new inputs fit narrow layouts at large text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      BrockmannApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrockmannCheckbox(
                  label: 'Include all automation lanes',
                  value: true,
                  onChanged: (_) {},
                ),
                BrockmannRangeSlider(
                  label: 'region',
                  values: const RangeValues(.2, .8),
                  onChanged: (_) {},
                ),
                BrockmannSearchField(controller: controller),
                BrockmannStepper(label: 'voices', value: 4, onChanged: (_) {}),
                BrockmannAccordion(
                  title: 'Advanced settings',
                  expanded: true,
                  onChanged: (_) {},
                  child: const BrockmannText('Details'),
                ),
                BrockmannNavigationBar(
                  destinations: const [
                    BrockmannDestination('studio', BrockmannIcon.settings),
                    BrockmannDestination('library', BrockmannIcon.folder),
                  ],
                  selected: 0,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
