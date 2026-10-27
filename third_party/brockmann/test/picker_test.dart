import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder menuText(String value) =>
    find.descendant(of: find.byType(ListView), matching: find.text(value));
void main() {
  testWidgets('Wide selection carries one label to the exact closed value', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    int selected = 1, commits = 0;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) => Scaffold(
            body: Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 400,
                child: BrockmannPicker(
                  label: 'output',
                  options: const ['one', 'two', 'a longer third option'],
                  selected: selected,
                  onChanged: (v) => set(() {
                    selected = v;
                    commits++;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final closed = tester.getTopLeft(find.text('two'));
    await tester.tap(find.byType(BrockmannPicker));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(menuText('two')), closed);
    final source = tester.getTopLeft(menuText('a longer third option'));
    await tester.tap(menuText('a longer third option'));
    await tester.pump();
    expect(selected, 2);
    expect(commits, 1);
    final carry = find.byKey(const ValueKey('brockmann-picker-carry'));
    expect(tester.getTopLeft(carry), source);
    final destination = tester.getTopLeft(
      find.descendant(
        of: find.byType(BrockmannPicker),
        matching: find.text('a longer third option'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final midway = tester.getTopLeft(carry);
    expect((midway - closed).distance, lessThan((source - closed).distance));
    await tester.pumpAndSettle();
    expect(carry, findsNothing);
    expect(tester.getTopLeft(find.text('a longer third option')), destination);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Keyboard arrows and End commit the highlighted choice once', (
    tester,
  ) async {
    int selected = 0;
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) => BrockmannPage(
            child: BrockmannPicker(
              label: 'output',
              options: List.generate(30, (i) => 'option $i'),
              selected: selected,
              onChanged: (i) => set(() => selected = i),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(BrockmannPicker));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(menuText('option 29'), findsOneWidget);
    expect(selected, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 29);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Early cancellation preserves value and remains animated', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    int commits = 0;
    await tester.pumpWidget(
      BrockmannApp(
        home: BrockmannPage(
          child: BrockmannPicker(
            label: 'output',
            options: const ['one', 'two', 'three'],
            selected: 0,
            onChanged: (_) => commits++,
          ),
        ),
      ),
    );
    final before = tester.getTopLeft(find.text('one'));
    await tester.tap(find.byType(BrockmannPicker));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final carry = find.byKey(const ValueKey('brockmann-picker-carry'));
    expect(carry, findsOneWidget);
    expect(tester.getTopLeft(carry), before);
    await tester.pump(const Duration(milliseconds: 100));
    expect(carry, findsOneWidget);
    await tester.pumpAndSettle();
    expect(commits, 0);
    expect(tester.getTopLeft(find.text('one')), before);
  });

  testWidgets(
    'Wide overflow aligns a late selected item and scrolls in place',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        BrockmannApp(
          home: BrockmannPage(
            child: Padding(
              padding: const EdgeInsets.only(top: 200),
              child: BrockmannPicker(
                label: 'output',
                options: List.generate(40, (i) => 'option $i'),
                selected: 32,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final before = tester.getTopLeft(find.text('option 32'));
      await tester.tap(find.byType(BrockmannPicker));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(menuText('option 32')), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(menuText('option 0'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('The first keyboard step glides from the existing selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      BrockmannApp(
        home: BrockmannPage(
          child: BrockmannPicker(
            label: 'output',
            options: const ['one', 'two', 'three'],
            selected: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(BrockmannPicker));
    await tester.pumpAndSettle();
    final ring = find.byKey(const ValueKey('brockmann-picker-focus'));
    final start = tester.getTopLeft(ring);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(tester.getTopLeft(ring), start);
    await tester.pump(const Duration(milliseconds: 70));
    final halfway = tester.getTopLeft(ring);
    expect(halfway.dy, greaterThan(start.dy));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(ring).dy, greaterThan(halfway.dy));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });
}
