import 'dart:convert';

import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/debug_menu_page.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

const id = '12345678-1234-1234-1234-123456789abc';
Map<String, dynamic> deniedSnapshot() => {
  'accounts': [
    {
      'id': id,
      'label': 'Owner',
      'version': 1,
      'session_version': 1,
      'pass_version': 1,
      'pass_allowed': false,
    },
  ],
  'passes': [
    {'account_id': id, 'number': '12345', 'version': 1},
  ],
  'cursor': 1,
  'protocol': 2,
  'sync': 'automatic',
  'pass_testing_expires_at':
      DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch /
      1000,
};

// The owner allows the pass, but only approved people may use it.
Map<String, dynamic> approvalSnapshot() {
  final snapshot = deniedSnapshot();
  (snapshot['accounts'] as List).single['pass_allowed'] = true;
  return {...snapshot, 'pass_agreements_required': true};
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() {
    ServerSessions.active?.close();
    ServerSessions.active = null;
  });

  test(
    'the testing password is never saved and an old saved one is removed',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'pass_testing_${'x' * 64}': '{"password":"old"}',
      });
      final client = SessionServerClient(
        'https://example.com',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'expires_at':
                  DateTime.now()
                      .add(const Duration(minutes: 5))
                      .millisecondsSinceEpoch /
                  1000,
            }),
            200,
          ),
        ),
      );
      addTearDown(client.close);
      await client.enablePassTesting('saved-test-password');
      expect(client.passTestingActive, isTrue);
      final stored = jsonEncode(await const FlutterSecureStorage().readAll());
      expect(stored, isNot(contains('saved-test-password')));
      final restored = SessionServerClient('https://example.com');
      addTearDown(restored.close);
      await restored.restorePassTesting();
      expect(restored.passTestingActive, isFalse);
    },
  );

  test('testing key is request-scoped and test-only pass numbers never enter the persisted snapshot', () async {
    final requests = <http.Request>[];
    final client = SessionServerClient(
      'https://example.com',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/api/debug/pass-testing') {
          return http.Response(
            jsonEncode({
              'expires_at':
                  DateTime.now()
                      .add(const Duration(minutes: 5))
                      .millisecondsSinceEpoch /
                  1000,
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    client.snapshot = deniedSnapshot();
    await client.enablePassTesting('test-daily-password');
    // The owner's switch on the server wins over testing.
    expect(client.passNumber(id), isNull);
    expect(client.canUsePass(id), isFalse);
    client.snapshot = approvalSnapshot();
    expect(client.passNumber(id), '12345');
    expect((client.cacheSnapshot['passes'] as List).single['number'], isNull);
    expect(
      jsonEncode(client.cacheSnapshot),
      isNot(contains('test-daily-password')),
    );
    final response = await client.proxy(id, 'pass-token', [0, 0, 0, 0, 0]);
    await response.stream.drain<void>();
    expect(requests.last.headers['x-pass-test-key'], 'test-daily-password');
    await client.disablePassTesting();
    expect(client.passNumber(id), isNull);
    final normal = await client.proxy(id, 'pass-token', [0, 0, 0, 0, 0]);
    await normal.stream.drain<void>();
    expect(requests.last.headers.containsKey('x-pass-test-key'), isFalse);
  });

  test(
    'testing expires automatically and clears permission exceptions',
    () async {
      final client = SessionServerClient(
        'https://example.com',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'expires_at':
                  DateTime.now()
                      .add(const Duration(seconds: 1))
                      .millisecondsSinceEpoch /
                  1000,
            }),
            200,
          ),
        ),
      );
      addTearDown(client.close);
      client.snapshot = approvalSnapshot();
      await client.enablePassTesting('test-password');
      expect(client.canUsePass(id), isTrue);
      expect(client.testingExpiryFor(id), isNotNull);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(client.passTestingActive, isFalse);
      expect(client.canUsePass(id), isFalse);
      expect(client.passNumber(id), isNull);
    },
  );

  testWidgets(
    'debug testing switch asks for the daily password and can disable the exception',
    (tester) async {
      final client = SessionServerClient(
        'https://example.com',
        client: MockClient((request) async {
          if (request.url.path == '/api/debug/pass-testing') {
            expect(jsonDecode(request.body)['password'], 'test-password');
            return http.Response(
              jsonEncode({
                'expires_at':
                    DateTime.now()
                        .add(const Duration(minutes: 5))
                        .millisecondsSinceEpoch /
                    1000,
              }),
              200,
            );
          }
          return http.Response(jsonEncode(deniedSnapshot()), 200);
        }),
      );
      ServerSessions.active = client;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DebugMenuPage(loadReport: (_) async => {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(CampusSwitch), 150);
      await tester.runAsync(() => tester.tap(find.byType(CampusSwitch)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      await tester.enterText(find.byType(TextField), 'test-password');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.text('Enable testing'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        client.passTestingActive,
        isTrue,
        reason:
            'Switch busy: ${tester.widget<CampusSwitch>(find.byType(CampusSwitch)).onChanged == null}; error: ${find.text("Could not enable testing. Check the daily password in the server panel.").evaluate().isNotEmpty}',
      );
      expect(
        tester.widget<CampusSwitch>(find.byType(CampusSwitch)).value,
        isTrue,
      );
      await tester.runAsync(() => tester.tap(find.byType(CampusSwitch)));
      await tester.pumpAndSettle();
      expect(client.passTestingActive, isFalse);
      expect(client.accounts.single['pass_allowed'], isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
