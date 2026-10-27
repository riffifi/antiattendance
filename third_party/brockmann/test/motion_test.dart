import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Retarget preserves position and velocity, then sleeps at rest', (
    tester,
  ) async {
    double target = 0, observed = 0;
    late StateSetter update;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) {
            update = set;
            return BrockmannMotion(
              value: target,
              milliseconds: 180,
              builder: (c, value) {
                observed = value;
                return const SizedBox();
              },
            );
          },
        ),
      ),
    );
    update(() => target = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(observed, inExclusiveRange(0, 1));
    final before = observed;
    update(() => target = 0);
    await tester.pump();
    expect(observed, closeTo(before, .000001));
    await tester.pump(const Duration(milliseconds: 1));
    // Velocity continues briefly toward the original destination, rather than snapping backward.
    expect(observed, greaterThan(before));
    await tester.pumpAndSettle();
    expect(observed, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Switch drag follows the finger and commits only on release', (
    tester,
  ) async {
    bool value = false;
    int commits = 0;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) => BrockmannPage(
            child: BrockmannSwitch(
              label: 'power',
              value: value,
              onChanged: (v) => set(() {
                value = v;
                commits++;
              }),
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(BrockmannSwitch));
    final gesture = await tester.startGesture(
      Offset(box.right - 44, box.center.dy),
    );
    await gesture.moveBy(const Offset(22, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(28, 0));
    await tester.pump();
    expect(commits, 0);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(value, true);
    expect(commits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Feather entry has spatial motion and a stagger', (tester) async {
    int page = 0;
    late StateSetter update;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) {
            update = set;
            return BrockmannPage(
              scroll: false,
              child: BrockmannPageSwitcher(
                selected: page,
                child: Column(
                  children: [
                    BrockmannFeather(index: 0, child: Text('heading $page')),
                    BrockmannFeather(index: 5, child: Text('last $page')),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    final settledX = tester.getTopLeft(find.text('heading 0')).dx;
    update(() => page = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getTopLeft(find.text('heading 1')).dx, greaterThan(settledX));
    final lateOpacity = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.text('last 1'),
            matching: find.byType(Opacity),
          ),
        )
        .map((o) => o.opacity);
    expect(lateOpacity, contains(0.0));
    await tester.pumpAndSettle();
    expect(find.text('heading 0'), findsNothing);
    expect(
      tester.getTopLeft(find.text('heading 1')).dx,
      closeTo(settledX, .01),
    );
  });

  testWidgets('Flat reorder moves neighbours and delivers adjusted index', (
    tester,
  ) async {
    final items = ['first', 'second', 'third'];
    int? destination;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) => BrockmannPage(
            scroll: false,
            child: BrockmannReorderableList(
              onReorder: (a, b) => set(() {
                destination = b;
                items.insert(b, items.removeAt(a));
              }),
              children: [
                for (final item in items)
                  SizedBox(
                    key: ValueKey(item),
                    height: 128,
                    child: BrockmannTile(label: item, value: '01', height: 96),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final start = tester.getCenter(find.text('first').first);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 260));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(destination, isNotNull);
    expect(items.first, isNot('first'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduced page motion fades without translation', (tester) async {
    int page = 0;
    late StateSetter update;
    await tester.pumpWidget(
      BrockmannApp(
        theme: const BrockmannThemeData(reduceMotion: true),
        home: StatefulBuilder(
          builder: (c, set) {
            update = set;
            return BrockmannPage(
              scroll: false,
              child: BrockmannPageSwitcher(
                selected: page,
                child: BrockmannFeather(index: 0, child: Text('page $page')),
              ),
            );
          },
        ),
      ),
    );
    final start = tester.getTopLeft(find.text('page 0'));
    update(() => page = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getTopLeft(find.text('page 1')), start);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  testWidgets('Rapid navigation preserves every outgoing page position', (
    tester,
  ) async {
    int page = 0;
    late StateSetter change;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) {
            change = set;
            return BrockmannPage(
              scroll: false,
              child: BrockmannPageSwitcher(
                selected: page,
                child: Column(
                  children: [
                    BrockmannFeather(index: 0, child: Text('heading $page')),
                    BrockmannFeather(index: 4, child: Text('row $page')),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    change(() => page = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final first = tester.getTopLeft(find.text('heading 1'));
    change(() => page = 2);
    await tester.pump();
    expect(tester.getTopLeft(find.text('heading 1')), first);
    await tester.pump(const Duration(milliseconds: 40));
    final outgoing = tester.getTopLeft(find.text('heading 1'));
    change(() => page = 3);
    await tester.pump();
    expect(tester.getTopLeft(find.text('heading 1')), outgoing);
    await tester.pumpAndSettle();
    expect(find.text('heading 3'), findsOneWidget);
    expect(find.text('heading 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
