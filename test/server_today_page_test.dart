import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/server_today_page.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'server_contract_test.dart' show response;
import 'server_workspace_test.dart' show settleNetwork;

Map<String, dynamic> dailyResults() => {
  'date': '12.11.2026',
  'group_name': 'Group A',
  'people': [
    {
      'id': 'a',
      'label': 'Alex',
      'group_id': 1,
      'group_name': 'Group A',
      'session': 'valid',
    },
    {
      'id': 'b',
      'label': 'Sam',
      'group_id': 2,
      'group_name': 'Group B',
      'session': 'expired',
    },
  ],
  'lessons': [
    {
      'subject': 'Algebra',
      'start': '09:00',
      'end': '10:30',
      'state': 'past',
      'groups': [
        {'id': 1},
      ],
      'marks': {
        'a': {'state': 'approved', 'message': 'Confirmed'},
      },
    },
    {
      'subject': 'Physics',
      'start': '11:00',
      'end': '12:30',
      'state': 'future',
      'groups': [
        {'id': 2},
      ],
    },
  ],
};

void main() {
  if (Platform.environment.containsKey('AA_TODAY_PREVIEW')) {
    setUpAll(() async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('packages/brockmann/Geist')..addFont(
            rootBundle.load('packages/brockmann/assets/fonts/Geist.ttf'),
          ))
          .load();
    });
  }
  testWidgets(
    'summary filters by attention and search without changing group counts',
    (tester) async {
      final client = SessionServerClient(
        'https://aa.example',
        client: MockClient((_) async => response(dailyResults())),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(AppThemeMode.dark),
          home: ServerTodayPage(api: AaServerApi(client)),
        ),
      );
      await settleNetwork(tester);
      expect(find.textContaining('1 of 1 confirmed'), findsOneWidget);
      expect(find.textContaining('0 of 1 confirmed'), findsOneWidget);
      expect(find.text('Algebra'), findsNothing);
      await tester.ensureVisible(find.text('Review · 1'));
      await tester.tap(find.text('Review · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsNothing);
      expect(find.text('Sam'), findsOneWidget);
      await tester.enterText(find.byType(BrockmannTextField), 'other');
      await tester.pumpAndSettle();
      expect(find.text('No people found'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Sam'), findsOneWidget);
      await tester.ensureVisible(find.text('Sam'));
      await tester.tap(find.text('Sam'));
      await tester.pumpAndSettle();
      expect(find.text('Later today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in [403, 503]) {
    testWidgets(
      'refresh $status removes denied data but retains recoverable results',
      (tester) async {
        var count = 0;
        final client = SessionServerClient(
          'https://aa.example',
          client: MockClient(
            (_) async =>
                ++count == 1 ? response(dailyResults()) : response({}, status),
          ),
        );
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: ServerTodayPage(api: AaServerApi(client)),
          ),
        );
        await settleNetwork(tester);
        await tester.runAsync(
          () => tester
              .widget<CampusRefresh>(find.byType(CampusRefresh))
              .onRefresh(),
        );
        await settleNetwork(tester);
        expect(
          find.text('Alex'),
          status == 403 ? findsNothing : findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(count, 2);
      },
    );
  }

  testWidgets('schedule failure does not claim there are no classes', (
    tester,
  ) async {
    final client = SessionServerClient(
      'https://aa.example',
      client: MockClient(
        (_) async => response({
          'schedule_error': 'Timetable unavailable',
          'lessons': [],
          'people': [],
        }),
      ),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(home: ServerTodayPage(api: AaServerApi(client))),
    );
    await settleNetwork(tester);
    expect(find.text('Timetable unavailable'), findsOneWidget);
    expect(find.text('No classes'), findsNothing);
  });

  for (final mode in [
    AppThemeMode.light,
    AppThemeMode.dark,
    AppThemeMode.amoled,
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('summary fits 320dp in $mode at $scale text', (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        final data = dailyResults();
        (data['people'] as List).first['label'] =
            'Alexandria Verylongname Morgan';
        final client = SessionServerClient(
          'https://aa.example',
          client: MockClient((_) async => response(data)),
        );
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(mode),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: ServerTodayPage(api: AaServerApi(client)),
            ),
          ),
        );
        await settleNetwork(tester);
        await tester.scrollUntilVisible(
          find.text('Alexandria Verylongname Morgan'),
          150,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.text('Alexandria Verylongname Morgan')),
          alignment: 0.3,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Alexandria Verylongname Morgan').hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.text('Alexandria Verylongname Morgan'));
        await tester.pumpAndSettle();
        expect(find.text('09:00–10:30 · Algebra'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final dir = Platform.environment['AA_TODAY_PREVIEW'];
        if (dir != null) {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(dir).create(recursive: true);
            await File('$dir/${mode.name}-$scale.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
