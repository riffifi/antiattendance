import 'package:antiattendance/editorial_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets(
    'completed actions have distinct feedback; cancelled and disabled taps do not',
    (tester) async {
      final feedback = <Object?>[];
      var actions = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            feedback.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                EditorialAction(
                  onPressed: () => actions++,
                  filled: true,
                  child: const Text('Primary'),
                ),
                EditorialAction(
                  onPressed: () => actions++,
                  child: const Text('Secondary'),
                ),
                const EditorialAction(child: Text('Disabled')),
              ],
            ),
          ),
        ),
      );
      final primarySurface = find.ancestor(
        of: find.text('Primary'),
        matching: find.byType(AnimatedContainer),
      );
      final restingColor =
          (tester.widget<AnimatedContainer>(primarySurface).decoration!
                  as BoxDecoration)
              .color;
      final cancelled = await tester.startGesture(
        tester.getCenter(find.text('Primary')),
      );
      await tester.pump();
      final primary = find.ancestor(
        of: find.text('Primary'),
        matching: find.byType(AnimatedContainer),
      );
      final pressed =
          tester.widget<AnimatedContainer>(primary).decoration!
              as BoxDecoration;
      expect(pressed.color, isNot(restingColor));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(feedback, isEmpty);
      expect(actions, 0);
      await tester.tap(find.text('Disabled'));
      expect(feedback, isEmpty);
      await tester.tap(find.text('Primary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Secondary'));
      await tester.pumpAndSettle();
      expect(actions, 2);
      expect(feedback, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.selectionClick',
      ]);
    },
  );
}
