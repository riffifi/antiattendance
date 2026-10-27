import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/session_share_page.dart';
import 'package:antiattendance/study_summary.dart';
import 'package:antiattendance/study_summary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final (size, scale) in [
    (const Size(320, 480), 1.4),
    (const Size(800, 360), 1.2),
    (const Size(1024, 768), 1.0),
  ]) {
    Widget app(Widget page) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: page,
    );

    void viewport(WidgetTester tester) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('QR transfer stays readable and actions reachable at $size', (
      tester,
    ) async {
      viewport(tester);
      await tester.pumpWidget(
        app(
          const SessionSharePage(
            accounts: [
              SavedAccount(
                id: 'a',
                label: 'Alex Morgan',
                cookie: 'test-session',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final qr = find.byType(QrImageView);
      expect(qr, findsOneWidget);
      final qrRect = tester.getRect(qr);
      expect(qrRect.width, lessThanOrEqualTo(size.width - 64));
      expect(qrRect.left, greaterThanOrEqualTo(32));
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Show code'), 100);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show code'));
      await tester.tap(find.text('Show code'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'summary uses separate readable cards and a bounded column at $size',
      (tester) async {
        viewport(tester);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          studySummaryChannel,
          (_) async => jsonEncode({
            'id': '2026-10-13',
            'at': 0,
            'people': [
              for (final name in [
                'Alex Morgan with a longer surname',
                'Sam Rivera',
              ])
                {
                  'name': name,
                  'counts': '2/3',
                  'lines': [
                    '09:00 Mathematics — Confirmed',
                    '11:00 Physics — Not recorded',
                  ],
                },
            ],
          }),
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(studySummaryChannel, null),
        );
        await tester.pumpWidget(app(const StudySummaryPage()));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(ListView)).width,
          lessThanOrEqualTo(640),
        );
        final scrollable = find.byType(Scrollable).first;
        double offset() =>
            tester.state<ScrollableState>(scrollable).position.pixels;
        final firstBottom =
            tester.getBottomLeft(find.byType(CampusPanel).first).dy + offset();
        await tester.scrollUntilVisible(
          find.text('Sam Rivera'),
          100,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        final second = find.ancestor(
          of: find.text('Sam Rivera'),
          matching: find.byType(CampusPanel),
        );
        expect(
          tester.getTopLeft(second).dy + offset() - firstBottom,
          closeTo(12, .01),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
