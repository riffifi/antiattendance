import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'haptics_test.dart' show Haptics, Audio;

void main() {
  testWidgets(
    'Accessible moves commit once with a landing tick and respect haptic mute',
    (tester) async {
      final haptics = Haptics();
      final feedback = BrockmannFeedbackController(
        backend: Audio(),
        hapticBackend: haptics,
      );
      addTearDown(feedback.dispose);
      final items = ['a', 'b', 'c'];
      await tester.pumpWidget(
        BrockmannApp(
          feedback: feedback,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, set) => BrockmannReorderableList(
                onReorder: (a, b) =>
                    set(() => items.insert(b, items.removeAt(a))),
                children: [
                  for (final item in items)
                    BrockmannTile(
                      key: ValueKey(item),
                      label: item,
                      value: '01',
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      VoidCallback moveLater() => tester
          .widget<Semantics>(
            find.byWidgetPredicate(
              (w) => w is Semantics && w.key == const ValueKey('a'),
            ),
          )
          .properties
          .customSemanticsActions!
          .entries
          .firstWhere((e) => e.key.label == 'Move later')
          .value;
      moveLater()();
      await tester.pumpAndSettle();
      expect(items, ['b', 'a', 'c']);
      expect(haptics.gestures, [false]);
      await feedback.configure(haptics: BrockmannHapticMode.off);
      moveLater()();
      await tester.pumpAndSettle();
      expect(items, ['b', 'c', 'a']);
      expect(haptics.gestures, [false]);
    },
  );
  for (final axis in Axis.values) {
    for (final size in BrockmannTileSize.values) {
      testWidgets(
        '${axis.name} ${size.name} reorder outlines only the tile and pulses once per phase',
        (tester) async {
          tester.view.physicalSize = const Size(800, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final haptics = Haptics();
          final feedback = BrockmannFeedbackController(
            backend: Audio(),
            hapticBackend: haptics,
          );
          addTearDown(feedback.dispose);
          final order = ['a', 'b', 'c'];
          var page = 0;
          final height = size == BrockmannTileSize.small
              ? 88.0
              : size == BrockmannTileSize.large
              ? 192.0
              : 128.0;
          await tester.pumpWidget(
            BrockmannApp(
              feedback: feedback,
              home: Scaffold(
                body: BrockmannPageSwitcher(
                  selected: page,
                  pageCount: 2,
                  onChanged: (v) => page = v,
                  child: Center(
                    child: SizedBox(
                      width: 720,
                      height: axis == Axis.vertical ? 900 : height + 20,
                      child: StatefulBuilder(
                        builder: (c, set) => BrockmannReorderableList(
                          axis: axis,
                          spacing: 12,
                          onReorder: (a, b) =>
                              set(() => order.insert(b, order.removeAt(a))),
                          children: [
                            for (final item in order)
                              Padding(
                                key: ValueKey(item),
                                padding: const EdgeInsets.only(bottom: 20),
                                child: BrockmannTile(
                                  key: ValueKey('tile-$item'),
                                  label: item,
                                  value: '01',
                                  size: size,
                                  width: axis == Axis.horizontal ? 180 : null,
                                  onPressed: () {},
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          final tile = find.byKey(const ValueKey('tile-a'));
          final bounds = tester.getSize(tile);
          final touch = await tester.startGesture(tester.getCenter(tile));
          await tester.pump(const Duration(milliseconds: 260));
          await tester.pump(const Duration(milliseconds: 100));
          final outline = find.byKey(
            const ValueKey('brockmann-reorder-outline'),
          );
          expect(outline, findsOneWidget);
          expect(tester.getSize(outline), bounds);
          expect(haptics.gestures, [true]);
          await touch.moveBy(
            axis == Axis.vertical ? const Offset(0, 20) : const Offset(20, 0),
          );
          await tester.pump(const Duration(milliseconds: 16));
          final movement = axis == Axis.vertical
              ? Offset(0, (bounds.height + 32) * 1.6)
              : const Offset(300, 0);
          for (var step = 0; step < 16; step++) {
            await touch.moveBy(movement / 16);
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(haptics.gestures, [true]);
          await touch.up();
          await tester.pumpAndSettle();
          expect(order.first, isNot('a'));
          expect(haptics.gestures, [true, false]);
          expect(page, 0);
          expect(outline, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
