import 'dart:convert';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/aa_id_page.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

Map<String, dynamic> grant(String access, String refresh, {int ttl = 600}) => {
  'access_token': access,
  'access_expires_at': DateTime.now().millisecondsSinceEpoch / 1000 + ttl,
  'refresh_token': refresh,
  'session_id': 'session-1',
  'user': {'id': 'user-1', 'group_id': 4242, 'group_name': 'ИКБО-01-24'},
};

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AaId.reset();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('AA ID address may include a path and is normalized', () {
    expect(
      AaIdClient.validateAddress('https://aa.example/id').toString(),
      'https://aa.example/id/',
    );
    for (final bad in [
      'ftp://aa.example',
      'https://user:pw@aa.example',
      'https://aa.example/?x=1',
    ]) {
      expect(() => AaIdClient.validateAddress(bad), throwsFormatException);
    }
  });

  test('signs in with a Pulse session and keeps only AA ID tokens', () async {
    late http.Request seen;
    AaId.httpClient = () => MockClient((request) async {
      seen = request;
      return json(grant('access-1', 'refresh-1'));
    });
    await AaId.signIn('https://aa.example/id', 'session=pulse');
    expect(seen.url.toString(), 'https://aa.example/id/v1/auth/mirea');
    expect(jsonDecode(seen.body)['pulse_cookie'], 'session=pulse');
    expect(AaId.signedIn, isTrue);
    expect(AaId.session!.groupName, 'ИКБО-01-24');
    final stored = await const FlutterSecureStorage().readAll();
    expect(stored.values.join(), isNot(contains('session=pulse')));
    expect(await AaId.accessToken(), 'access-1');

    // A fresh start restores the session from secure storage.
    AaId.reset();
    await AaId.initialize();
    expect(AaId.session!.userId, 'user-1');
    expect(AaId.url, 'https://aa.example/id/');
  });

  test(
    'refreshes an expiring token once and signs out when rejected',
    () async {
      var refreshes = 0;
      AaId.httpClient = () => MockClient((request) async {
        if (request.url.path.endsWith('/v1/auth/mirea')) {
          return json(grant('access-1', 'refresh-1', ttl: 10));
        }
        refreshes++;
        final token = jsonDecode(request.body)['refresh_token'];
        return token == 'refresh-1'
            ? json(grant('access-2', 'refresh-2', ttl: 10))
            : json({'detail': 'Sign in again'}, 401);
      });
      await AaId.signIn('https://aa.example/id', 'session=pulse');
      final tokens = await Future.wait([
        AaId.accessToken(),
        AaId.accessToken(),
      ]);
      expect(tokens, ['access-2', 'access-2']);
      expect(refreshes, 1);
      await expectLater(
        AaId.accessToken(),
        throwsA(isA<AaIdException>().having((e) => e.status, 'status', 401)),
      );
      expect(AaId.signedIn, isFalse);
    },
  );

  test('session server requests carry the AA ID token', () async {
    AaId.httpClient = () =>
        MockClient((_) async => json(grant('access-1', 'refresh-1')));
    await AaId.signIn('https://aa.example/id', 'session=pulse');
    final headers = <String?>[];
    final server = SessionServerClient(
      'https://sessions.example',
      client: MockClient((request) async {
        headers.add(request.headers['authorization']);
        if (request.url.path == '/api/groups') {
          return json({'groups': []});
        }
        return http.Response(
          '{"detail":"AA ID sign-in required"}',
          401,
          headers: {'x-aaid-required': '1'},
        );
      }),
    );
    await server.groups();
    expect(headers.single, 'Bearer access-1');
    await expectLater(
      server.proxy('x', 'profile', [0, 0, 0, 0, 0]),
      throwsA(isA<http.ClientException>()),
    );
    expect(headers.last, 'Bearer access-1');
    server.close();
  });

  testWidgets('the app is hidden until AA ID sign-in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppThemeMode.light),
        home: const AaIdGate(child: Text('Home')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);
    expect(find.text('Sign in with MIREA'), findsOneWidget);

    AaId.httpClient = () =>
        MockClient((_) async => json(grant('access-1', 'refresh-1')));
    await tester.runAsync(
      () => AaId.signIn('https://aa.example/id', 'session=pulse'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });
}
