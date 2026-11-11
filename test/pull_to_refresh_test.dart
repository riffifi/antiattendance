import 'dart:async';

import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget page(
    Future<void> Function() refresh, {
    AppThemeMode mode = AppThemeMode.light,
    bool reduced = false,
    double scale = 1,
  }) => MaterialApp(
    theme: AppTheme.build(mode),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: CampusRefresh(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [Text('Content')],
        ),
      ),
    ),
  );

  Future<void> ready(WidgetTester tester, Widget target) async {
    await tester.pumpWidget(target);
    await tester.pumpAndSettle();
  }

  for (final mode in AppThemeMode.values) {
    testWidgets(
      '${mode.name} refresh uses a flat progress treatment and does not overlap requests',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pending = Completer<void>();
        var calls = 0;
        await ready(
          tester,
          page(
            () {
              calls++;
              return pending.future;
            },
            mode: mode,
            scale: 2,
          ),
        );
        await tester.drag(find.byType(ListView), const Offset(0, 420));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 100));
        expect(calls, 1);
        expect(find.text('Refreshing…'), findsOneWidget);
        expect(find.byType(BrockmannProgress), findsOneWidget);
        expect(find.byType(RefreshProgressIndicator), findsNothing);
        await tester.drag(find.byType(ListView), const Offset(0, 420));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(calls, 1);
        expect(tester.takeException(), isNull);
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.text('Refreshing…'), findsNothing);
        expect(find.byType(BrockmannProgress), findsNothing);
      },
    );
  }

  testWidgets('short pulls cancel without refreshing', (tester) async {
    var calls = 0;
    await ready(
      tester,
      page(() async {
        calls++;
      }),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 35));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(BrockmannProgress), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('release threshold is announced during a held drag', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final pending = Completer<void>();
    await ready(tester, page(() => pending.future));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, 420));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text('Release to refresh'), findsOneWidget);
    expect(find.bySemanticsLabel('Release to refresh'), findsOneWidget);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    pending.complete();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets(
    'reduced motion refresh still reports work without an animated spinner',
    (tester) async {
      final pending = Completer<void>();
      await ready(tester, page(() => pending.future, reduced: true));
      await tester.drag(find.byType(ListView), const Offset(0, 420));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Refreshing…'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
      pending.complete();
      await tester.pumpAndSettle();
    },
  );
}
