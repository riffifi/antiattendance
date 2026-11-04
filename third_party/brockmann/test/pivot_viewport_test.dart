import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'adaptive pivot retains one keyed form through swipes, rapid taps and resize',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final form = GlobalKey();
      var selected = 0;
      late StateSetter update;
      await tester.pumpWidget(
        BrockmannApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return BrockmannAdaptiveScaffold(
                title: 'AA',
                destinations: const ['people', 'schedule', 'passes'],
                selected: selected,
                onChanged: (value) => set(() => selected = value),
                body: Column(
                  children: [
                    TextFormField(key: form, initialValue: 'keep this draft'),
                    const Expanded(
                      child: ColoredBox(
                        color: Colors.white,
                        child: SizedBox.expand(key: ValueKey('swipe-space')),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = form.currentState;
      await tester.drag(
        find.byType(BrockmannPivotViewport),
        const Offset(-180, 0),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(selected, 1);
      expect(form.currentState, same(state));
      update(() => selected = 2);
      await tester.pump(const Duration(milliseconds: 40));
      update(() => selected = 0);
      await tester.pumpAndSettle();
      expect(find.text('keep this draft'), findsOneWidget);
      expect(form.currentState, same(state));
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();
      expect(find.byType(BrockmannNavigationList), findsOneWidget);
      expect(form.currentState, same(state));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'field selection, child gestures and cancelled drags do not change page',
    (tester) async {
      var selected = 0;
      final field = TextEditingController(text: 'Editable content');
      addTearDown(field.dispose);
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: BrockmannPivotViewport(
              selected: selected,
              pageCount: 3,
              onChanged: (value) => selected = value,
              child: Column(
                children: [
                  BrockmannTextField(label: 'name', controller: field),
                  const Expanded(
                    child: SizedBox.expand(key: ValueKey('space')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(TextFormField), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(selected, 0);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('space'))),
      );
      await gesture.moveBy(const Offset(-40, 0));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(selected, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion preserves swipe navigation and clamps the final page',
    (tester) async {
      var selected = 0;
      var changes = 0;
      await tester.pumpWidget(
        BrockmannApp(
          theme: const BrockmannThemeData(reduceMotion: true),
          home: StatefulBuilder(
            builder: (context, set) => Scaffold(
              body: BrockmannPivotViewport(
                selected: selected,
                pageCount: 2,
                onChanged: (value) => set(() {
                  selected = value;
                  changes++;
                }),
                child: const ColoredBox(
                  color: Colors.white,
                  child: SizedBox.expand(key: ValueKey('page')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.drag(
        find.byType(BrockmannPivotViewport),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(changes, 1);
      await tester.drag(
        find.byType(BrockmannPivotViewport),
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page heading reuses navigation hierarchy and keeps readable supporting text',
    (tester) async {
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: BrockmannNavigationScope(
              heading: 'people',
              headingVisible: true,
              child: const BrockmannPageHeader(
                title: 'people',
                subtitle: 'Choose an account',
                reuseNavigationHeading: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('people'), findsNothing);
      expect(find.text('Choose an account'), findsOneWidget);
      await tester.pumpWidget(
        BrockmannApp(
          home: const Scaffold(
            body: BrockmannPageHeader(
              title: 'people',
              subtitle: 'Choose an account',
              reuseNavigationHeading: true,
            ),
          ),
        ),
      );
      expect(find.text('people'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'selected pivot heading returns to the leading axis, including the last page',
    (tester) async {
      var selected = 0;
      late StateSetter update;
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, set) {
                    update = set;
                    return BrockmannPivot(
                      options: const ['people', 'schedule', 'passes'],
                      selected: selected,
                      onChanged: (value) => set(() => selected = value),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final index in [1, 2, 0]) {
        update(() => selected = index);
        await tester.pumpAndSettle();
        expect(
          tester
              .getTopLeft(find.text(['people', 'schedule', 'passes'][index]))
              .dx,
          closeTo(12, 1),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('selected full-size pivot is also the spoken page heading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: BrockmannPivot(
              options: const ['people', 'schedule'],
              selected: 0,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.text('people'))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.text('schedule'))
            .getSemanticsData()
            .flagsCollection
            .isHeader,
        isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });
}
