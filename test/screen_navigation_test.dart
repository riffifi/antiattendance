import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/screen_navigation.dart';
import 'package:antiattendance/screen_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets(
    'developer reveal requires five separate downward rail gestures at Attendance',
    (tester) async {
      var selected = 0;
      var revealed = false;
      var reveals = 0;
      var selector = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder: (context, update) => ScreenNavigation(
              selectorVisible: selector,
              selectedIndex: selected,
              debugVisible: revealed,
              onRevealDebug: () => update(() {
                revealed = true;
                selected = 4;
                reveals++;
              }),
              onSelected: (index) => update(() {
                selected = index;
                selector = false;
              }),
              onIndex: () => update(() => selector = true),
              child: const ColoredBox(
                key: ValueKey('page-body'),
                color: Colors.white,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      final rail = find.byKey(const ValueKey('screen-rail'));
      for (var i = 0; i < 5; i++) {
        await tester.drag(
          find.byKey(const ValueKey('page-body')),
          const Offset(0, 160),
        );
        await tester.pumpAndSettle();
      }
      expect(reveals, 0);
      // A single long drag produces many overscroll events but counts once.
      final gesture = await tester.startGesture(
        tester.getTopLeft(rail) + const Offset(25, 20),
      );
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reveals, 0);
      for (var i = 0; i < 3; i++) {
        await tester.drag(rail, const Offset(0, 140));
        await tester.pumpAndSettle();
      }
      expect(reveals, 0);
      // Cancelled and short gestures reset the sequence.
      final cancelled = await tester.startGesture(tester.getCenter(rail));
      await cancelled.moveBy(const Offset(0, 100));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      await tester.drag(rail, const Offset(0, 20));
      await tester.pumpAndSettle();
      // Ordinary navigation away from Attendance cannot reveal Developer.
      await tester.drag(rail, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.drag(rail, const Offset(0, 420));
      await tester.pumpAndSettle();
      expect(selected, 0);
      for (var i = 0; i < 4; i++) {
        await tester.drag(rail, const Offset(0, 140));
        await tester.pumpAndSettle();
        expect(reveals, 0);
      }
      await tester.drag(rail, const Offset(0, 140));
      await tester.pumpAndSettle();
      expect(reveals, 1);
      expect(selected, 4);
      expect(find.text('00'), findsOneWidget);
      await tester.tap(find.text('INDEX'));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenSelector), findsOneWidget);
      expect(find.byKey(const ValueKey('screen-selector-4')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selected column morphs to rail and swipes both ways with one tick',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      var selected = 0;
      var selector = true;
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
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
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder: (context, update) => ScreenNavigation(
              selectorVisible: selector,
              selectedIndex: selected,
              onIndex: () => update(() => selector = true),
              onSelected: (index) => update(() {
                selected = index;
                selector = false;
              }),
              child: Container(
                key: const ValueKey('content'),
                color: Colors.transparent,
                child: Text('Page $selected'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('screen-selector-3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(ScreenSelector), findsOneWidget);
      expect(find.text('Page 3'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(ScreenSelector), findsNothing);
      final rail = find.byKey(const ValueKey('screen-rail'));
      expect(tester.widget<PageView>(rail).controller!.page, 3);
      expect(tester.getRect(rail).width, 60);
      await tester.drag(rail, const Offset(0, 520));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(haptics, [
        'HapticFeedbackType.lightImpact',
        'HapticFeedbackType.selectionClick',
      ]);
      await tester.drag(rail, const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(haptics.length, 3);
      await tester.drag(rail, const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(haptics.length, 4);
      expect(haptics.last, 'HapticFeedbackType.lightImpact');
      await tester.drag(
        find.byKey(const ValueKey('content')),
        const Offset(0, 520),
      );
      await tester.pumpAndSettle();
      expect(selected, 3);
      await tester.tap(find.text('INDEX'));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenSelector), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'content keeps system insets and reduced motion opens immediately',
    (tester) async {
      var selector = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(800, 600),
              padding: EdgeInsets.only(top: 24, bottom: 34),
              disableAnimations: true,
            ),
            child: StatefulBuilder(
              builder: (context, update) => ScreenNavigation(
                selectorVisible: selector,
                selectedIndex: 0,
                onSelected: (_) => update(() => selector = false),
                onIndex: () {},
                child: Container(key: const ValueKey('safe-content')),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ScreenSelector), findsNothing);
      final rect = tester.getRect(find.byKey(const ValueKey('safe-content')));
      expect(rect.top, 24);
      expect(rect.bottom, 566);
      expect(rect.left, 60);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reduced motion swipes snap immediately even with muted tickers',
    (tester) async {
      var selected = 0;
      var selector = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: TickerMode(
              enabled: false,
              child: StatefulBuilder(
                builder: (context, update) => ScreenNavigation(
                  selectorVisible: selector,
                  selectedIndex: selected,
                  onIndex: () => update(() => selector = true),
                  onSelected: (index) => update(() {
                    selected = index;
                    selector = false;
                  }),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
      await tester.pumpAndSettle();
      final rail = find.byKey(const ValueKey('screen-rail'));
      await tester.drag(rail, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(tester.widget<PageView>(rail).controller!.page, 1);
      expect(
        tester
            .widget<PageView>(rail)
            .controller!
            .position
            .isScrollingNotifier
            .value,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
