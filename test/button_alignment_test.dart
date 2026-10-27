import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('text buttons center labels at text scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Column(
                children: [
                  CampusTextAction(label: 'back', onPressed: () {}),
                  SizedBox(
                    width: 96,
                    height: 100,
                    child: CampusTextAction(
                      label: 'more actions',
                      onPressed: () {},
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    height: 140,
                    child: CampusButton.text(
                      onPressed: () {},
                      child: const Text('Go\nlonger'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final label in ['back', 'more actions', 'Go\nlonger']) {
        final text = find.text(label);
        final surface = find.ancestor(
          of: text,
          matching: find.byType(AnimatedContainer),
        );
        expect(
          tester.getCenter(text).dx,
          closeTo(tester.getCenter(surface).dx, .01),
        );
        expect(
          tester.getCenter(text).dy,
          closeTo(tester.getCenter(surface).dy, .01),
        );
      }
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('Go\nlonger'),
      );
      final shortLine = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 2),
          )
          .single;
      final longLine = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 3, extentOffset: 9),
          )
          .single;
      expect(
        (shortLine.left + shortLine.right) / 2,
        closeTo((longLine.left + longLine.right) / 2, .01),
      );
      expect(
        tester.getSize(find.byType(CampusTextAction).first).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
