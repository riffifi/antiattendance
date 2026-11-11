import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget shell(Widget child, {bool reduced = false}) => MaterialApp(
    theme: AppTheme.build(AppThemeMode.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'checkbox tick preserves its target and respects reduced motion: $reduced',
      (tester) async {
        var selected = false;
        await tester.pumpWidget(
          shell(
            StatefulBuilder(
              builder: (context, update) => BrockmannCheckbox(
                label: 'Select',
                value: selected,
                onChanged: (value) => update(() => selected = value!),
              ),
            ),
            reduced: reduced,
          ),
        );
        final clip = find
            .descendant(
              of: find.byType(BrockmannCheckbox),
              matching: find.byType(ClipRect),
            )
            .last;
        final target = tester.getSize(find.byType(BrockmannCheckbox));
        expect(tester.getSize(clip).width, 0);
        await tester.tap(find.text('Select'));
        await tester.pump();
        if (!reduced) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.getSize(clip).width, inExclusiveRange(0, 16));
        } else {
          expect(tester.getSize(clip).width, 16);
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(clip).width, 16);
        expect(tester.getSize(find.byType(BrockmannCheckbox)), target);
      },
    );
  }

  testWidgets('disclosure content opens smoothly with its indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        const CampusDisclosure(
          title: 'Details',
          children: [SizedBox(height: 80)],
        ),
      ),
    );
    final closed = tester.getSize(find.byType(CampusDisclosure)).height;
    await tester.tap(find.text('Details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.getSize(find.byType(CampusDisclosure)).height,
      inExclusiveRange(closed, closed + 80),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CampusDisclosure)).height, closed + 80);
  });

  testWidgets('result reveal does not replay on ordinary rebuilds', (
    tester,
  ) async {
    var label = 'First';
    late StateSetter update;
    await tester.pumpWidget(
      shell(
        StatefulBuilder(
          builder: (context, setter) {
            update = setter;
            return CampusReveal(child: Text(label));
          },
        ),
      ),
    );
    final fade = find.descendant(
      of: find.byType(CampusReveal),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(fade).opacity, 0);
    await tester.pumpAndSettle();
    update(() => label = 'Second');
    await tester.pump();
    expect(tester.widget<Opacity>(fade).opacity, 1);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets(
    'changing labels expose only the current value to screen readers',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var value = 'Old';
      late StateSetter update;
      await tester.pumpWidget(
        shell(
          StatefulBuilder(
            builder: (context, setter) {
              update = setter;
              return CampusValueTransition(value);
            },
          ),
        ),
      );
      update(() => value = 'New');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getSemantics(find.text('New')).label, 'New');
      expect(
        tester
            .widget<ExcludeSemantics>(
              find
                  .ancestor(
                    of: find.text('Old'),
                    matching: find.byType(ExcludeSemantics),
                  )
                  .first,
            )
            .excluding,
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsNothing);
      semantics.dispose();
    },
  );
}
