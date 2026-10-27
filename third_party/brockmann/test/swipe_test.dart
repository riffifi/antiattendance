import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Finger scrubs turnstile and release retains feather entry', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) => Scaffold(
            body: BrockmannPageSwitcher(
              selected: selected,
              pageCount: 3,
              onChanged: (v) => set(() => selected = v),
              child: BrockmannFeather(index: 0, child: Text('page $selected')),
            ),
          ),
        ),
      ),
    );
    Transform turn(String label) => tester.widget<Transform>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Transform))
          .last,
    );
    final finger = await tester.startGesture(const Offset(300, 200));
    await finger.moveBy(const Offset(-25, 0));
    await tester.pump();
    final first = turn('page 0').transform.entry(0, 0);
    await finger.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(turn('page 0').transform.entry(0, 0), lessThan(first));
    expect(turn('page 0').transform.entry(0, 3), 0);
    await tester.pump(const Duration(milliseconds: 300));
    await finger.up();
    await tester.pumpAndSettle();
    expect(selected, 0);
    expect(turn('page 0').transform.entry(0, 0), 1);
    final swipe = await tester.startGesture(const Offset(300, 200));
    await swipe.moveBy(const Offset(-140, 0));
    await tester.pump();
    final release = turn('page 0').transform.entry(0, 0);
    await swipe.up();
    await tester.pump();
    expect(selected, 1);
    expect(turn('page 0').transform.entry(0, 0), release);
    await tester.pump(const Duration(milliseconds: 100));
    expect(turn('page 0').transform.entry(0, 0), lessThan(release));
    final feather = tester.widget<Transform>(
      find
          .ancestor(of: find.text('page 1'), matching: find.byType(Transform))
          .first,
    );
    expect(feather.transform.entry(0, 3), greaterThan(0));
    await tester.pumpAndSettle();
    expect(find.text('page 0'), findsNothing);
    expect(turn('page 1').transform.entry(0, 0), 1);
  });

  testWidgets(
    'Title swipe selects one neighbour without manually panning labels',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        BrockmannApp(
          home: StatefulBuilder(
            builder: (c, set) => Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 320,
                  child: BrockmannPivot(
                    options: const ['one', 'two', 'three', 'four'],
                    selected: selected,
                    onChanged: (v) => set(() => selected = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('one')).dx, 12);
      final finger = await tester.startGesture(const Offset(250, 30));
      await finger.moveBy(const Offset(-100, 0));
      await tester.pump();
      expect(selected, 0);
      expect(tester.getTopLeft(find.text('one')).dx, 12);
      await finger.up();
      await tester.pumpAndSettle();
      expect(selected, 1);
      for (var i = 0; i < 2; i++) {
        await tester.drag(find.byType(BrockmannPivot), const Offset(-100, 0));
        await tester.pumpAndSettle();
      }
      expect(selected, 3);
      expect(tester.getBottomRight(find.text('four')).dx, closeTo(308, .1));
    },
  );
}
