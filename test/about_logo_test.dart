import 'package:antiattendance/about_logo.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> showBadge(WidgetTester tester, {bool reduceMotion = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: const Scaffold(body: Center(child: AboutLogo())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final object = find.byKey(const ValueKey('about-logo-rotation'));
  final front = find.byKey(const ValueKey('about-logo-front'));
  final back = find.byKey(const ValueKey('about-logo-back'));
  final portrait = find.byKey(const ValueKey('about-logo-portrait'));
  final faceTransform = find.byKey(const ValueKey('about-logo-face-transform'));

  testWidgets('drag reveals old logo, release springs back to the front', (
    tester,
  ) async {
    await showBadge(tester);
    final resting = tester.widget<Transform>(faceTransform).transform.clone();
    final gesture = await tester.startGesture(tester.getCenter(object));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump();
    expect(back, findsOneWidget);
    expect(portrait, findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(back, findsOneWidget); // No animation until released.
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(back, findsOneWidget); // A spring, not an instant reset.
    await tester.pumpAndSettle();
    expect(front, findsOneWidget);
    final returned = tester.widget<Transform>(faceTransform).transform;
    for (var i = 0; i < 16; i++) {
      expect(returned.storage[i], closeTo(resting.storage[i], .01));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('opposite drag reveals portrait and preserves it on reversal', (
    tester,
  ) async {
    await showBadge(tester);
    final gesture = await tester.startGesture(tester.getCenter(object));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-140, 0));
    await tester.pump();
    expect(portrait, findsOneWidget);
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump();
    expect(portrait, findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(front, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new drag interrupts the spring and cancellation returns home', (
    tester,
  ) async {
    await showBadge(tester);
    await tester.drag(object, const Offset(180, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final gesture = await tester.startGesture(tester.getCenter(object));
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();
    final held = tester.widget<Transform>(faceTransform).transform.clone();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Transform>(faceTransform).transform, held);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(front, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('badge has no shadow or visible rotation instructions', (
    tester,
  ) async {
    await showBadge(tester);
    expect(find.textContaining('Drag to rotate'), findsNothing);
    final decorations = tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(AboutLogo),
        matching: find.byType(DecoratedBox),
      ),
    );
    for (final widget in decorations) {
      expect((widget.decoration as BoxDecoration).boxShadow, isNull);
    }
  });

  testWidgets('reduced motion resets immediately after release', (
    tester,
  ) async {
    await showBadge(tester, reduceMotion: true);
    final gesture = await tester.startGesture(tester.getCenter(object));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.moveBy(const Offset(160, 0));
    await tester.pump();
    expect(back, findsOneWidget);
    await gesture.up();
    await tester.pump();
    expect(front, findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
