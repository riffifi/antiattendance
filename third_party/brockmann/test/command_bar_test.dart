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
      expect(tester.getSize(bar).height, 48);
      expect(find.byTooltip('add account').hitTestable(), findsNothing);
      expect(actions, 0);
      await tester.drag(
        find.bySemanticsLabel('Expand app bar'),
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
}
