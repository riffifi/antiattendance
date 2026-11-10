import 'dart:convert';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/session_server_sync.dart';
import 'package:antiattendance/study_summary.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const ownId = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> nativeSnapshot() => {
  'protocol': 2,
  'sync': 'automatic',
  'cursor': 1,
  'accounts': [
    {
      'id': ownId,
      'label': 'Alex Morgan',
      'state': 'valid',
      'own': true,
      'version': 1,
      'session_version': 1,
      'pass_version': 0,
      'group_id': 42,
    },
  ],
};
http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Map<String, dynamic> tokenGrant({bool linked = true}) => {
  'access_token': 'access',
  'refresh_token': 'refresh',
  'session_id': 'session',
  'access_expires_at': DateTime.now().millisecondsSinceEpoch / 1000 + 600,
  'linked': linked,
  'user': {'id': 'person', 'group_id': 42, 'group_name': 'Group A'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AaId.reset();
    ServerSessions.active = null;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    ServerSessions.active?.close();
    ServerSessions.active = null;
    AaId.reset();
  });

  test(
    'server QR workflow uses job secret and claims only AA ID tokens',
    () async {
      final seen = <http.Request>[];
      final api = AaIdClient(
        defaultAaIdUrl,
        client: MockClient((request) async {
          seen.add(request);
          return switch (request.url.path) {
            '/v1/auth/logins' => response({'id': 'job', 'token': 'capability'}),
            '/v1/auth/logins/job' => response({'status': 'complete'}),
            '/v1/auth/logins/job/claim' => response(tokenGrant(linked: false)),
            _ => throw StateError('Removed auth endpoint used'),
          };
        }),
      );
      final job = await api.startLogin();
      await api.loginState(job['id'] as String, job['token'] as String);
      final grant = await api.claimLogin('job', 'capability');
      expect(seen.map((r) => r.method), ['POST', 'GET', 'POST']);
      expect(seen.every((r) => r.body.isEmpty), isTrue);
      expect(
        seen.skip(1).every((r) => r.headers['x-login-token'] == 'capability'),
        isTrue,
      );
      expect(grant.linked, isFalse);
      await AaId.acceptLogin(defaultAaIdUrl, grant);
      final stored = (await const FlutterSecureStorage().readAll()).values
          .join();
      expect(stored, isNot(contains('capability')));
      expect(AaId.session!.linked, isFalse);
      api.close();
    },
  );

  test(
    'native metadata sync never uploads legacy cookies or group outbox',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'pulse_accounts_v1': jsonEncode([
          {'id': 'local', 'label': 'Old', 'cookie': 'session=private'},
        ]),
      });
      final paths = <String>[];
      final client = SessionServerClient(
        'https://aa.example',
        client: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.body, isNot(contains('private')));
          if (request.url.path == '/api/accounts') {
            return response(nativeSnapshot());
          }
          throw StateError('Removed or unexpected endpoint ${request.url}');
        }),
      );
      ServerSessions.active = client;
      await SessionAutoSync.sync();
      expect(client.serverManaged, isTrue);
      expect(client.cacheSnapshot.containsKey('passes'), isFalse);
      expect(paths, ['/api/accounts']);
    },
  );

  test(
    'marking sends scoped JSON once and retains individual failures',
    () async {
      var calls = 0;
      final client = SessionServerClient(
        'https://aa.example',
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, '/site/mark');
          expect(jsonDecode(request.body), {
            'qr': 'https://attendance-app.mirea.ru/?token=test',
            'account_ids': [ownId],
            'own_group': false,
            'lesson_start': 1793944800,
          });
          return response({
            'results': [
              {'id': ownId, 'state': 'expired', 'message': 'Sign in again'},
            ],
          });
        }),
      );
      final result = await AaServerApi(client).mark(
        'https://attendance-app.mirea.ru/?token=test',
        [ownId, ownId],
        lessonStart: 1793944800,
      );
      expect(result.single['state'], 'expired');
      expect(calls, 1);
      client.close();
    },
  );

  test('lost mutation response is not retried', () async {
    var calls = 0;
    final client = SessionServerClient(
      'https://aa.example',
      client: MockClient((request) async {
        calls++;
        throw http.ClientException('connection lost');
      }),
    );
    await expectLater(
      AaServerApi(client).mark('qr', [ownId]),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 1);
    client.close();
  });

  test('day marks and summaries never copy another class result into a missing cell', () {
    final first = <String, dynamic>{
      'subject': 'Math',
      'start': '09:00',
      'end': '10:30',
      'marks': {
        ownId: {'state': 'approved', 'message': 'Confirmed'},
      },
      'mirea': {},
    };
    final second = <String, dynamic>{
      'subject': 'Physics',
      'start': '11:00',
      'end': '12:30',
      'marks': {},
      'mirea': {ownId: null},
    };
    expect(dayMark(first, ownId)?['state'], 'approved');
    expect(dayMark(second, ownId), isNull);
    expect(
      dayMark({
        'mirea': {ownId: 'present'},
      }, ownId)?['state'],
      'approved',
    );
    final summary = buildServerStudySummary({
      'date': '10.11.2026',
      'lessons': [first, second],
      'people': [
        {'id': ownId, 'label': 'Alex', 'session': 'expired'},
      ],
    }).single;
    final person = (summary['people'] as List).single as Map;
    expect(person['counts'], '1/2');
    expect((person['lines'] as List).last, endsWith('—'));
    expect(person['sessionExpired'], isTrue);
    expect(
      DateTime.fromMillisecondsSinceEpoch(summary['at'] as int, isUtc: true),
      DateTime.utc(2026, 11, 10, 9, 30),
    );
  });
}
