import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/session_server_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const id = '12345678-1234-1234-1234-123456789abc';
Map<String, dynamic> snapshot() => {
  'accounts': [
    {
      'id': id,
      'label': 'Owner',
      'version': 1,
      'pass_version': 1,
      'session_version': 1,
      'state': 'valid',
      'group_id': 769,
      'pass_allowed': true,
    },
  ],
  'passes': [
    {'account_id': id, 'number': '12345', 'version': 1},
  ],
  'cursor': 1,
  'protocol': 2,
  'sync': 'automatic',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ServerSessions.active?.close();
    ServerSessions.active = null;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    ServerSessions.active?.close();
    ServerSessions.active = null;
  });

  test(
    'server address supports HTTP and HTTPS, rejects credentials and paths',
    () {
      for (final address in [
        'http://192.168.1.20:8080',
        'https://sessions.example.com/',
        'http://[::1]:8080',
      ]) {
        expect(SessionServerClient.validateAddress(address).host, isNotEmpty);
      }
      for (final address in [
        'ftp://example.com',
        'https://user:key@example.com',
        'https://example.com/path',
        'http://example.com?token=x',
        'http://example.com#x',
        'http://example.com:99999',
      ]) {
        expect(
          () => SessionServerClient.validateAddress(address),
          throwsFormatException,
        );
      }
    },
  );

  test('fetch needs only the URL and rejects leaked cookies', () async {
    final server = SessionServerClient(
      'http://192.168.1.20:8080',
      client: MockClient((request) async {
        expect(request.url.path, '/api/accounts');
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
        return http.Response(jsonEncode(snapshot()), 200);
      }),
    );
    await server.fetch();
    expect(server.accounts.single['label'], 'Owner');
    expect(server.passNumber(id), '12345');

    server.close();
    final leaked = snapshot();
    (leaked['accounts'] as List).first['cookie'] = 'secret';
    final invalid = SessionServerClient(
      'http://localhost',
      client: MockClient((_) async => http.Response(jsonEncode(leaked), 200)),
    );
    await expectLater(invalid.fetch(), throwsFormatException);
    invalid.close();
  });

  test('remote RPC strips cookies and uses the configured origin', () async {
    final server = SessionServerClient('http://192.168.1.20:8080');
    final rpc = ServerRpcClient(
      server,
      id,
      transport: MockClient((request) async {
        expect(
          request.url.toString(),
          'http://192.168.1.20:8080/api/accounts/$id/rpc/pass-issue',
        );
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.headers['x-pulse-token'], 'fresh-token');
        expect(request.headers.containsKey('cookie'), isFalse);
        expect(request.bodyBytes, [0, 0, 0, 0, 0]);
        return http.Response('', 200);
      }),
    );
    await rpc.send(
      http.Request(
          'POST',
          Uri.parse(
            'https://pulse.mirea.ru/rtu_tc.rtu_attend.humanpass.HumanPassService/GetDigitalPass',
          ),
        )
        ..headers['authorization'] = 'Bearer fresh-token'
        ..headers['cookie'] = 'must-not-leave-device'
        ..bodyBytes = [0, 0, 0, 0, 0],
    );
    await expectLater(
      rpc.send(http.Request('POST', Uri.parse('https://other.host/anything'))),
      throwsA(isA<http.ClientException>()),
    );
    rpc.close();
    server.close();
  });

  test(
    'HTTP proxy authentication is distinct from an expired Pulse session',
    () async {
      final server = SessionServerClient(
        'http://localhost',
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(
        server.proxy(id, 'profile', [0, 0, 0, 0, 0]),
        throwsA(isA<http.ClientException>()),
      );

      server.close();
    },
  );

  test(
    'configured server metadata loads offline without pass numbers',
    () async {
      final store = AccountStore();
      final server = SessionServerClient(
        'http://localhost',
        client: MockClient((_) async => http.Response('', 503)),
      )..snapshot = snapshot();
      ServerSessions.active = server;
      await ServerSessions.saveSnapshot();
      final accounts = await store.load();
      expect(serverAccountId(accounts.single.cookie), id);
      final cached = await const FlutterSecureStorage().read(
        key: 'session_server_snapshot_v1',
      );
      expect(cached, isNot(contains('"12345"')));
      await ServerSessions.disconnect();
      expect(await store.load(), isEmpty);
    },
  );

  testWidgets(
    'settings migrate legacy configuration and show only the server URL',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'session_server_config_v1': jsonEncode({
          'url': 'http://192.168.1.20:8080',
          'key': 'private-device-key',
        }),
        'session_server_snapshot_v1': jsonEncode(snapshot()),
      });
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const SessionServerPage()),
      );
      await tester.pumpAndSettle();
      expect(find.text('http://192.168.1.20:8080'), findsWidgets);
      final fields = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .toList();
      expect(fields.length, 1);
      final saved = await const FlutterSecureStorage().read(
        key: 'session_server_config_v1',
      );
      expect(jsonDecode(saved!), {'url': 'http://192.168.1.20:8080'});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
