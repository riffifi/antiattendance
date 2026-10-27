import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Overlay band fills the viewport and text clears fallback decoration',
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        BrockmannApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold();
            },
          ),
        ),
      );
      showBrockmannDialog(
        context,
        title: 'confirm',
        message: 'Keep this change?',
      );
      await tester.pumpAndSettle();
      final surface = find
          .ancestor(of: find.text('confirm'), matching: find.byType(Material))
          .first;
      expect(tester.getRect(surface).left, 0);
      expect(
        tester.getRect(surface).right,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
      final paragraph = tester.widget<RichText>(
        find.descendant(
          of: find.text('confirm'),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.text.style!.decoration, TextDecoration.none);
      await tester.tap(find.text('close'));
      await tester.pumpAndSettle();
      expect(find.text('confirm'), findsNothing);
    },
  );
}
