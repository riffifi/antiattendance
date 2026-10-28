import 'dart:convert';

import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/pass_people.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/today_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// The mock server answers on the real event loop.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Widget app(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: child),
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => ServerSessions.active = null);

  testWidgets('Today lists each lesson with everyone\'s marks', (tester) async {
    ServerSessions.active = SessionServerClient(
      'https://aa.example',
      client: MockClient((request) async {
        expect(request.url.path, '/api/me/today');
        return json({
          'date': '28.10.2026',
          'group_id': 1,
          'group_name': 'ГР-1',
          'schedule_error': null,
          'mirea': {},
          'people': [
            {'id': 'a', 'label': 'Anna', 'session': 'valid', 'own': true},
            {'id': 'b', 'label': 'Boris', 'session': 'valid', 'own': false},
            {'id': 'c', 'label': 'Cat', 'session': 'expired', 'own': false},
          ],
          'lessons': [
            {
              'subject': 'Physics',
              'start': '10:40',
              'end': '12:10',
              'type': 'ПР',
              'location': 'A-101',
              'state': 'now',
              'groups': [
                {'id': 1, 'name': 'ГР-1'},
              ],
              'marks': {
                'a': {'state': 'approved', 'created': 1793180000},
                'b': null,
                'c': null,
              },
              'mirea': {'a': 'absent', 'b': 'present', 'c': null},
            },
          ],
        });
      }),
    );
    await tester.pumpWidget(app(const TodayPage(active: true)));
    await settle(tester);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('10:40–12:10'), findsOneWidget);
    // Anna marked in the app, Boris only in the MIREA journal: both count.
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.textContaining('Marked in the MIREA journal'), findsOneWidget);
    expect(find.textContaining('not connected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pass request is allowed after a confirmation', (tester) async {
    final calls = <String>[];
    var requests = [
      {
        'id': 'r1',
        'account_id': 'b',
        'label': 'Boris',
        'username': 'boris',
        'group_name': 'ГР-2',
      },
    ];
    ServerSessions.active = SessionServerClient(
      'https://aa.example',
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        switch (request.url.path) {
          case '/api/me/pass':
            return json({
              'pass_allowed': true,
              'people': [],
              'requests': requests,
            });
          case '/api/me/passes':
            return json({
              'passes': [
                {
                  'account_id': 'c',
                  'label': 'Cat',
                  'username': null,
                  'group_name': 'ГР-3',
                  'pass_allowed': true,
                },
              ],
              'requests': [],
            });
          case '/api/me/pass/requests/r1/allow':
            requests = [];
            return json({
              'pass_allowed': true,
              'people': [
                {
                  'kind': 'aaid',
                  'id': 'b',
                  'account_id': 'b',
                  'label': 'Boris',
                },
              ],
              'requests': [],
            });
        }
        return json({'detail': 'Not found'}, 404);
      }),
    );
    await tester.pumpWidget(
      app(const SingleChildScrollView(child: PassSharingSection())),
    );
    await settle(tester);
    expect(find.text('Boris (@boris)'), findsOneWidget);
    expect(find.text('Cat'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(find.text('Allow your pass?'), findsOneWidget);
    await tester.tap(find.text('Allow').last);
    await settle(tester);
    expect(calls, contains('POST /api/me/pass/requests/r1/allow'));
    expect(find.text('Boris (@boris)'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
