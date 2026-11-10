import 'dart:io';
import 'dart:convert';

import 'package:antiattendance/campus_design.dart';

import 'dart:ui' as ui;

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/server_workspace.dart';
import 'package:antiattendance/screen_navigation.dart';
import 'package:antiattendance/server_today_page.dart';
import 'package:antiattendance/server_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'server_contract_test.dart' show ownId, nativeSnapshot, response;

const lesson = {
  'subject': 'Software engineering',
  'type': 'Lecture',
  'teacher': 'A. Ivanov',
  'location': 'A-204',
  'start': '09:00',
  'end': '10:30',
  'lesson_start': 1793944800,
};
Map<String, dynamic> stateFixture() => {
  'me': {'connected': true, 'group_id': 42, 'group_name': 'Group A'},
  'selected_lesson': lesson,
  'available_lessons': [lesson],
  'active': 'now',
  'groups': [
    {'id': 42, 'name': 'Group A'},
  ],
  'people': [
    {
      'id': ownId,
      'label': 'Alex Morgan',
      'group_id': 42,
      'group_name': 'Group A',
      'session': 'valid',
      'own': true,
      'inside': true,
    },
    {
      'id': 'second',
      'label': 'Sam Rivera',
      'group_id': 42,
      'group_name': 'Group A',
      'session': 'expired',
      'inside': null,
    },
  ],
};

Future<void> settleNetwork(WidgetTester tester) async {
  // HTTP response streams and platform storage alternate with frame work.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AaId.reset();
    ServerSessions.active = null;
    FlutterSecureStorage.setMockInitialValues({});
  });
  if (Platform.environment.containsKey('SERVER_PREVIEW_DIR')) {
    setUpAll(() async {
      for (final (family, file) in [
        ('Geist', 'Geist.ttf'),
        ('Geist Mono', 'GeistMono.ttf'),
      ]) {
        await (FontLoader('packages/brockmann/$family')..addFont(
              rootBundle.load('packages/brockmann/assets/fonts/$file'),
            ))
            .load();
      }
    });
  }
  for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$mode server screens fit 320dp at $scale text size', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final paths = <String>[];
        final client = SessionServerClient(
          'https://aa.example',
          client: MockClient((request) async {
            paths.add(request.url.path);
            return response(switch (request.url.path) {
              '/api/accounts' => nativeSnapshot(),
              '/site/state' => stateFixture(),
              '/site/schedule' => {
                'group_name': 'Group A',
                'monday': '2026-11-09',
                'days': [
                  {
                    'date': '2026-11-10',
                    'today': true,
                    'lessons': [lesson],
                  },
                ],
              },
              '/api/me/pass' => {
                'pass_allowed': true,
                'people': [],
                'requests': [],
              },
              '/api/me/passes' => {'passes': [], 'requests': []},
              _ => throw StateError('Unexpected request: ${request.url.path}'),
            });
          }),
        );
        addTearDown(client.close);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(mode),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: ServerWorkspace(
                client: client,
                settings: AppSettingsStore(),
                onLanguageChanged: (_) {},
                themeMode: mode,
                onThemeModeChanged: (_) {},
              ),
            ),
          ),
        );
        await settleNetwork(tester);
        if (scale > 1) {
          await tester.scrollUntilVisible(
            find.text('Alex Morgan'),
            150,
            scrollable: find
                .descendant(
                  of: find.byKey(const PageStorageKey('server-attendance')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await settleNetwork(tester);
        }
        expect(find.text('Alex Morgan'), findsOneWidget);
        for (final (tab, label) in [
          'attendance',
          'schedule',
          'passes',
          'settings',
        ].indexed) {
          if (tab != 0) {
            tester
                .widget<ScreenNavigation>(find.byType(ScreenNavigation))
                .onSelected(tab);
            await settleNetwork(tester);
          }
          expect(tester.takeException(), isNull);
          if (Platform.environment['SERVER_PREVIEW_DIR'] case final String dir
              when scale == 1) {
            final render =
                boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await render.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(dir).create(recursive: true);
              await File('$dir/${mode.name}-$label.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
        expect(paths, isNot(contains('/api/accounts/import')));
        expect(paths.any((p) => p.contains('/rpc/')), isFalse);
        await tester.pumpWidget(const SizedBox());
        await settleNetwork(tester);
      });
    }
  }

  testWidgets('today keeps missing per-class cells as a dash', (tester) async {
    final client = SessionServerClient(
      'https://aa.example',
      client: MockClient(
        (_) async => response({
          'date': '10.11.2026',
          'group_name': 'Group A',
          'people': [
            {'id': ownId, 'label': 'Alex'},
          ],
          'lessons': [
            {
              ...lesson,
              'marks': {
                ownId: {'message': 'Confirmed', 'state': 'approved'},
              },
            },
            {
              ...lesson,
              'subject': 'Physics',
              'marks': {},
              'mirea': {ownId: null},
            },
          ],
        }),
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
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'attendance submission excludes selected people hidden by group filter',
    (tester) async {
      Map<String, dynamic>? submitted;
      final data = stateFixture();
      (data['groups'] as List).add({'id': 43, 'name': 'Group B'});
      final friend = (data['people'] as List)[1] as Map;
      friend['session'] = 'valid';
      friend['group_id'] = 43;
      friend['group_name'] = 'Group B';
      final client = SessionServerClient(
        'https://aa.example',
        client: MockClient((request) async {
          if (request.url.path == '/api/accounts') {
            return response(nativeSnapshot());
          }
          if (request.url.path == '/site/state') return response(data);
          if (request.url.path == '/site/mark') {
            submitted = jsonDecode(request.body) as Map<String, dynamic>;
            return response({
              'results': [
                {'id': 'second', 'state': 'approved', 'message': 'Confirmed'},
              ],
            });
          }
          throw StateError('Unexpected request ${request.url}');
        }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ServerWorkspace(
            client: client,
            settings: AppSettingsStore(),
            onLanguageChanged: (_) {},
            themeMode: AppThemeMode.light,
            onThemeModeChanged: (_) {},
          ),
        ),
      );
      await settleNetwork(tester);
      await tester.tap(find.text('All groups'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Group B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Paste'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(CampusTextField),
        'https://attendance-app.mirea.ru/?token=lesson',
      );
      await tester.tap(find.text('Submit'));
      await settleNetwork(tester);
      expect(submitted?['account_ids'], ['second']);
      expect(submitted?['lesson_start'], lesson['lesson_start']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
