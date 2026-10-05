import 'package:antiattendance/expressive.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final sheet in [true, false]) {
    testWidgets(
      'predictive back ${sheet ? 'sheet' : 'dialog'} follows, cancels and commits',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    if (sheet) {
                      showExpressiveSheet<void>(
                        context: context,
                        builder: (_) =>
                            const SizedBox(height: 240, child: Text('Popup')),
                      );
                    } else {
                      showExpressiveDialog<void>(
                        context: context,
                        builder: (_) =>
                            const AlertDialog(content: Text('Popup')),
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final observer = tester.state(
          find.byType(PredictiveBackSurface),
        ) as WidgetsBindingObserver;
        final route = ModalRoute.of(
          tester.element(find.byType(PredictiveBackSurface)),
        )!;
        PredictiveBackEvent event(double progress) =>
            PredictiveBackEvent.fromMap({
              'progress': progress,
              'swipeEdge': 0,
              'touchOffset': [0.0, 300.0],
            });
        expect(observer.handleStartBackGesture(event(0)), isTrue);
        observer.handleUpdateBackGestureProgress(event(.6));
        await tester.pump();
        expect(route.animation!.value, closeTo(.4, .001));
        observer.handleCancelBackGesture();
        await tester.pumpAndSettle();
        expect(find.text('Popup'), findsOneWidget);
        expect(route.animation!.value, 1);
        expect(observer.handleStartBackGesture(event(0)), isTrue);
        observer.handleUpdateBackGestureProgress(event(.8));
        observer.handleCommitBackGesture();
        await tester.pumpAndSettle();
        expect(find.text('Popup'), findsNothing);
        expect(find.text('Open'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('back closes the pass picker before leaving its screen', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: AppPassPicker(
            enabled: true,
            hint: 'Your account',
            items: const [
              M3EDropdownItem(value: 'a', label: 'Alice', selected: true),
              M3EDropdownItem(value: 'b', label: 'Bob'),
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppPassPicker));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsNothing);
    expect(find.byType(AppPassPicker), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expressive menu closes on back and selects actions', (
    tester,
  ) async {
    Object? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
        home: Scaffold(
          body: AppActionMenu(
            entries: const [M3EMenuEntry(value: 'rename', label: 'Rename')],
            onSelected: (value) => choice = value,
            anchorBuilder: (_, open) =>
                M3EButton.text(onPressed: open, child: const Text('Actions')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.byType(M3EMenu), findsOneWidget);
    expect(find.byType(PopupMenuItem<M3EMenuEntry>), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(choice, 'rename');
    expect(find.text('Rename'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
