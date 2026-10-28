import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {double textScale = 1}) => MaterialApp(
  theme: const BrockmannThemeData().material,
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(320, 640),
      textScaler: TextScaler.linear(textScale),
    ),
    child: Material(
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

Future<void> sized(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  test('window classes and value fallback', () {
    expect(BrockmannWindowSize.of(320), BrockmannWindowSize.compact);
    expect(BrockmannWindowSize.of(700), BrockmannWindowSize.medium);
    expect(BrockmannWindowSize.of(900), BrockmannWindowSize.expanded);
    expect(BrockmannWindowSize.of(1400), BrockmannWindowSize.large);
    final wide = BrockmannLayout.forWidth(1400);
    expect(wide.value(compact: 1, medium: 2), 2);
    expect(wide.inset, 48);
    expect(BrockmannLayout.forWidth(360).inset, 24);
    expect(BrockmannLayout.forWidth(360).columns, 4);
  });

  test('grid column count', () {
    expect(BrockmannGrid.columnsFor(320, 160, 16), 1);
    expect(BrockmannGrid.columnsFor(336, 160, 16), 2);
    expect(BrockmannGrid.columnsFor(2000, 160, 16, 4), 4);
  });

  testWidgets('grid lays out equal columns and wraps', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 336,
          child: BrockmannGrid(
            children: [
              for (var i = 0; i < 3; i++)
                SizedBox(key: ValueKey(i), height: 20),
            ],
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey(0))).width, 160);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey(2))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const ValueKey(0))).dy),
    );
  });

  testWidgets('columns stack below breakpoint', (tester) async {
    Widget columns(double w) => host(
      SizedBox(
        width: w,
        child: const BrockmannColumns(
          children: [
            SizedBox(key: ValueKey('a'), height: 10),
            SizedBox(key: ValueKey('b'), height: 10),
          ],
        ),
      ),
    );
    await tester.pumpWidget(columns(320));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('b'))).dy,
      greaterThan(0),
    );
    await tester.pumpWidget(columns(800));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('b'))).dx,
      greaterThan(tester.getTopLeft(find.byKey(const ValueKey('a'))).dx),
    );
  });

  testWidgets('new components fit 320 dp at 200% text', (tester) async {
    await tester.pumpWidget(
      host(
        textScale: 2,
        SizedBox(
          width: 320,
          height: 640,
          child: SingleChildScrollView(
            child: BrockmannStack(
              children: [
                const BrockmannPageHeader(
                  title: 'A long settings title',
                  overline: 'project',
                  subtitle: 'Wraps instead of clipping.',
                ),
                BrockmannSection(
                  title: 'Section',
                  description: 'Description',
                  trailing: BrockmannButton.text(
                    label: 'edit',
                    onPressed: () {},
                  ),
                  children: const [
                    BrockmannStat(label: 'latency', value: '12.4 ms'),
                    BrockmannPropertyList(
                      entries: {'sample rate': '48 kHz', 'buffer': '256'},
                    ),
                    BrockmannPlaceholder(lines: 3),
                  ],
                ),
                BrockmannButtonBar(
                  children: [
                    BrockmannButton.primary(label: 'save', onPressed: () {}),
                    BrockmannButton(
                      label: 'delete forever',
                      destructive: true,
                      icon: BrockmannIcon.trash,
                      onPressed: () {},
                    ),
                  ],
                ),
                BrockmannButton.primary(
                  label: 'continue',
                  icon: BrockmannIcon.arrowRight,
                  expand: true,
                  onPressed: () {},
                ),
                BrockmannListItem(
                  label: 'Audio output',
                  secondary: 'USB interface',
                  leading: BrockmannIcon.settings,
                  trailing: const BrockmannBadge(
                    label: 'live',
                    tone: BrockmannTone.accent,
                  ),
                  chevron: true,
                  onPressed: () {},
                ),
                BrockmannBanner(
                  title: 'Export failed',
                  message: 'The disk is full.',
                  tone: BrockmannTone.danger,
                  action: BrockmannButton.text(
                    label: 'retry',
                    onPressed: () {},
                  ),
                ),
                BrockmannStepper(label: 'voices', value: 4, onChanged: (_) {}),
                const BrockmannTextField(
                  label: 'Name',
                  hint: 'untitled',
                  helper: 'Shown in the library.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('stepper exposes adjustable semantics', (tester) async {
    double value = 2;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (c, set) => BrockmannStepper(
            label: 'voices',
            value: value,
            max: 3,
            onChanged: (v) => set(() => value = v),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Increase voices'));
    await tester.pump();
    expect(value, 3);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('adaptive scaffold switches pivot and list', (tester) async {
    var selected = 0;
    Widget app() => BrockmannApp(
      home: StatefulBuilder(
        builder: (c, set) => BrockmannAdaptiveScaffold(
          title: 'app',
          destinations: const ['inbox', 'archive'],
          selected: selected,
          onChanged: (i) => set(() => selected = i),
          body: Text('body $selected'),
        ),
      ),
    );
    await sized(tester, const Size(400, 800));
    await tester.pumpWidget(app());
    expect(find.byType(BrockmannPivot), findsOneWidget);
    await sized(tester, const Size(1200, 800));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(BrockmannNavigationList), findsOneWidget);
    await tester.tap(find.text('archive'));
    await tester.pumpAndSettle();
    expect(find.text('body 1'), findsOneWidget);
  });

  testWidgets('adaptive scaffold retains editing across breakpoints', (
    tester,
  ) async {
    await sized(tester, const Size(400, 800));
    await tester.pumpWidget(
      BrockmannApp(
        home: BrockmannAdaptiveScaffold(
          destinations: const ['inbox', 'archive'],
          selected: 0,
          onChanged: (_) {},
          body: const BrockmannTextField(label: 'Draft'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'unfinished draft');
    final state = tester.state(find.byType(TextFormField));
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TextFormField)), same(state));
    expect(find.text('unfinished draft'), findsOneWidget);
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TextFormField)), same(state));
    expect(find.text('unfinished draft'), findsOneWidget);
  });

  testWidgets('split view shows detail and Back returns', (tester) async {
    var detail = true;
    await sized(tester, const Size(400, 800));
    await tester.pumpWidget(
      BrockmannApp(
        home: StatefulBuilder(
          builder: (c, set) => BrockmannSplitView(
            list: const Text('list'),
            detail: const Text('detail'),
            showDetail: detail,
            onCloseDetail: () => set(() => detail = false),
          ),
        ),
      ),
    );
    expect(find.text('detail'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('list'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('page title and readable width on tablets', (tester) async {
    await sized(tester, const Size(1400, 900));
    await tester.pumpWidget(
      const BrockmannApp(
        home: BrockmannPage(
          title: 'Settings',
          child: SizedBox(key: ValueKey('c'), height: 10, width: 4000),
        ),
      ),
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('c'))).width, 960);
  });
}
