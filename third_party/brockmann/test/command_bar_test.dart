import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ellipsis expands, Back collapses, drag minimizes and restores commands',
    (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: BrockmannCommandBar(
              commands: [
                BrockmannCommand(
                  icon: const Icon(Icons.add),
                  label: 'add account',
                  onPressed: () => actions++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = find.byType(BrockmannCommandBar);
      expect(tester.getSize(bar).height, 64);
      await tester.tap(find.bySemanticsLabel('Expand app bar'));
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, greaterThan(64));
      expect(find.text('add account').hitTestable(), findsOneWidget);
      final context = tester.element(bar);
      await Navigator.of(context).maybePop();
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, 64);
      final handle = find.bySemanticsLabel('Expand app bar');
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(tester.getSize(bar).height, lessThan(64));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, BrockmannCommandBar.minimizedExtent);
      expect(find.byTooltip('add account').hitTestable(), findsNothing);
      expect(actions, 0);
      final minimized = tester.getRect(bar);
      final handleRect = tester.getRect(
        find.bySemanticsLabel('Expand app bar'),
      );
      await tester.dragFrom(
        Offset(handleRect.center.dx, minimized.center.dy),
        const Offset(0, -90),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, greaterThan(64));
      await tester.tap(find.byTooltip('add account'));
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(tester.getSize(bar).height, 64);
    },
  );

  testWidgets(
    'cancelled drag returns to rest and four large-text commands fit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              bottomNavigationBar: BrockmannCommandBar(
                commands: [
                  for (var i = 0; i < 4; i++)
                    BrockmannCommand(
                      icon: const Icon(Icons.add),
                      label: 'command $i',
                      onPressed: i == 3 ? null : () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      final bar = find.byType(BrockmannCommandBar);
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Expand app bar')),
      );
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, 64);
      await tester.tap(find.bySemanticsLabel('Expand app bar'));
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, greaterThan(88));
      expect(
        tester.getRect(find.text('command 3')).bottom,
        lessThanOrEqualTo(568),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('commands stay centered while the ellipsis sits in the corner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: const BrockmannThemeData(style: BrockmannStyle.wp8).material,
        home: Scaffold(
          bottomNavigationBar: BrockmannCommandBar(
            commands: [
              BrockmannCommand(
                icon: const Icon(Icons.add),
                label: 'left',
                onPressed: () {},
              ),
              BrockmannCommand(
                icon: const Icon(Icons.remove),
                label: 'right',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(BrockmannCommandBar));
    final left = tester.getCenter(find.byTooltip('left'));
    final right = tester.getCenter(find.byTooltip('right'));
    final ellipsis = tester.getCenter(find.bySemanticsLabel('Expand app bar'));
    expect((left.dx + right.dx) / 2, closeTo(bar.center.dx, 1));
    expect(left.dy, closeTo(right.dy, 1));
    expect(ellipsis.dy, lessThan(left.dy));
    expect(ellipsis.dx, greaterThan(right.dx));
  });
  testWidgets('four command glyphs do not collide with the ellipsis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: BrockmannCommandBar(
            commands: [
              for (var i = 0; i < 4; i++)
                BrockmannCommand(
                  icon: const Icon(Icons.add),
                  label: 'action $i',
                  onPressed: () {},
                ),
            ],
          ),
        ),
      ),
    );
    final glyph = tester.getRect(find.byIcon(Icons.add).last);
    final handle = tester.getRect(find.bySemanticsLabel('Expand app bar'));
    expect(glyph.right, lessThan(handle.left));
    expect(tester.takeException(), isNull);
  });
}
