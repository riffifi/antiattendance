import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Custom calendar respects bounds, leap day and draft cancellation',
    (tester) async {
      DateTime? result;
      await tester.pumpWidget(
        BrockmannApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => BrockmannButton(
                label: 'date',
                onPressed: () async {
                  result = await showBrockmannDatePicker(
                    c,
                    initialDate: DateTime(2028, 2, 27),
                    firstDate: DateTime(2028, 2, 27),
                    lastDate: DateTime(2028, 3, 2),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(BrockmannCalendar), findsOneWidget);
      final disabled = find.byKey(const ValueKey('brockmann-date-2028-2-26'));
      await tester.ensureVisible(disabled);
      await tester.tap(disabled);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BrockmannCalendar>(find.byType(BrockmannCalendar))
            .value
            .day,
        27,
      );
      final leap = find.byKey(const ValueKey('brockmann-date-2028-2-29'));
      await tester.ensureVisible(leap);
      await tester.tap(leap);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BrockmannCalendar>(find.byType(BrockmannCalendar))
            .value
            .day,
        29,
      );
      await tester.ensureVisible(find.text('cancel'));
      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('date'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(leap);
      await tester.tap(leap);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('use date'));
      await tester.tap(find.text('use date'));
      await tester.pumpAndSettle();
      expect(result, DateTime(2028, 2, 29));
    },
  );
  testWidgets('Custom time wheels commit a draft without Material clock UI', (
    tester,
  ) async {
    TimeOfDay? result;
    await tester.pumpWidget(
      BrockmannApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => BrockmannButton(
              label: 'time',
              onPressed: () async {
                result = await showBrockmannTimePicker(
                  c,
                  initialTime: const TimeOfDay(hour: 9, minute: 30),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('time'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsNothing);
    expect(find.byType(BrockmannTimePicker), findsOneWidget);
    final wheel = find.byKey(const ValueKey('brockmann-time-minute'));
    await tester.ensureVisible(wheel);
    await tester.drag(wheel, const Offset(0, -80));
    await tester.pumpAndSettle();
    final draft = tester
        .widget<BrockmannTimePicker>(find.byType(BrockmannTimePicker))
        .value;
    expect(draft.minute, greaterThan(30));
    expect(result, isNull);
    await tester.ensureVisible(find.text('use time'));
    await tester.tap(find.text('use time'));
    await tester.pumpAndSettle();
    expect(result, draft);
  });
  testWidgets('Familiar glyphs support labelled search and menu actions', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'query');
    addTearDown(controller.dispose);
    late BuildContext context;
    Finder glyph(BrockmannIcon icon) =>
        find.byWidgetPredicate((w) => w is BrockmannGlyph && w.icon == icon);
    await tester.pumpWidget(
      BrockmannApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return BrockmannSearchField(controller: controller);
            },
          ),
        ),
      ),
    );
    expect(glyph(BrockmannIcon.search), findsOneWidget);
    expect(glyph(BrockmannIcon.x), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Clear search'));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(glyph(BrockmannIcon.x), findsNothing);
    showBrockmannActionSheet(
      context,
      title: 'session',
      entries: const [
        BrockmannMenuEntry(
          value: 'add',
          label: 'add',
          icon: BrockmannIcon.plus,
        ),
        BrockmannMenuEntry(
          value: 'copy',
          label: 'copy',
          icon: BrockmannIcon.copy,
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(glyph(BrockmannIcon.plus), findsOneWidget);
    expect(glyph(BrockmannIcon.copy), findsOneWidget);
    expect(find.text('copy'), findsOneWidget);
    await tester.tap(find.text('copy'));
    await tester.pumpAndSettle();
    showBrockmannContextMenu(
      context,
      position: const Offset(40, 200),
      showIcons: false,
      entries: const [
        BrockmannMenuEntry(
          value: 'add',
          label: 'add',
          icon: BrockmannIcon.plus,
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(glyph(BrockmannIcon.plus), findsNothing);
    expect(find.text('add'), findsOneWidget);
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
  });
  testWidgets('Calendar and time editor fit 320 dp at 200 percent text', (
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
    await tester.pumpWidget(
      BrockmannApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  BrockmannCalendar(
                    value: DateTime(2028, 2, 27),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                    onChanged: (_) {},
                  ),
                  BrockmannTimePicker(
                    value: const TimeOfDay(hour: 9, minute: 30),
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
