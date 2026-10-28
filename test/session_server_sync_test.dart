import 'dart:convert';
import 'dart:async';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/sensitive_data.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/session_server_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const accountId = '12345678-1234-1234-1234-123456789abc';

class Backend {
  bool offline = false;
  Completer<void>? passGate;
  Completer<void>? passStarted;
  Map<String, dynamic>? account;
  String? number;
  int imports = 0, passWrites = 0, cursor = 0;
  final importVersions = <int?>[], passVersions = <int>[];
  Map<String, dynamic> snapshot() => {
    'protocol': 2,
    'sync': 'automatic',
    'cursor': cursor,
    'accounts': [if (account != null) Map<String, dynamic>.from(account!)],
    'passes': [
      if (account != null)
        {
          'account_id': accountId,
          'number': number,
          'version': account!['pass_version'],
        },
    ],
  };
  void sharedPass(String value) {
    number = value;
    account!['pass_version']++;
    account!['version']++;
    cursor++;
  }

  void sharedSession() {
    account!['session_version']++;
    account!['version']++;
    cursor++;
  }

  Future<http.Response> handle(http.Request request) async {
    expect(request.headers.containsKey('authorization'), isFalse);
    if (offline) return http.Response('', 503);
    if (request.method == 'GET' && request.url.path == '/api/accounts') {
      return http.Response(jsonEncode(snapshot()), 200);
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.url.path == '/api/accounts/import') {
      imports++;
      importVersions.add(body['expected_session_version'] as int?);
      final expected = body['expected_session_version'];
      if (account != null &&
          expected != null &&
          expected != account!['session_version']) {
        return http.Response('{}', 409);
      }
      if (account == null) {
        account = {
          'id': accountId,
          'label': body['label'],
          'version': 1,
          'session_version': 1,
          'pass_version': 0,
          'state': 'valid',
        };
        cursor++;
      } else if (expected != null) {
        sharedSession();
      }
      return http.Response(jsonEncode(account), 200);
    }
    if (request.url.path.endsWith('/pass')) {
      if (passGate != null) {
        final gate = passGate!;
        passGate = null;
        passStarted?.complete();
        await gate.future;
      }
      passWrites++;
      passVersions.add(body['expected_version'] as int);
      if (body['expected_version'] != account!['pass_version']) {
        return http.Response('{}', 409);
      }
      sharedPass(body['number'] as String);
      return http.Response(jsonEncode(account), 200);
    }
    return http.Response('{}', 404);
  }

  SessionServerClient client() =>
      SessionServerClient('http://localhost:8080', client: MockClient(handle));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ServerSessions.active = null;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() async {
    await SessionAutoSync.sync();
    ServerSessions.active?.close();
    ServerSessions.active = null;
  });
  const local = SavedAccount(
    id: 'local',
    label: 'Owner',
    cookie: 'session=initial',
  );

  Future<Map<String, String>> oldPhone() async {
    // What an older version left on the phone.
    FlutterSecureStorage.setMockInitialValues({
      'pulse_accounts_v1': jsonEncode([local.toJson()]),
      'nfc_pass_local': jsonEncode({'number': '987654321', 'session': 'x'}),
      'session_sync_abc': jsonEncode({
        'local': {'pass_number': '987654321', 'own_pass_number': '987654321'},
      }),
      'pass_testing_abc': jsonEncode({'password': 'daily', 'expires_at': 1}),
      'session_server_mappings_v1': '{}',
      'nfc_queue_settings': jsonEncode({'seconds': 5}),
      'aa_id_session_v1': 'kept',
    });
    return const FlutterSecureStorage().readAll();
  }

  test('accounts an older version kept are uploaded once and then removed with every pass', () async {
    await oldPhone();
    final backend = Backend();
    ServerSessions.active = backend.client();
    await SensitiveData.purge();
    expect(backend.imports, 1);
    expect(backend.passWrites, 0);
    final left = await const FlutterSecureStorage().readAll();
    expect(left.keys, containsAll(['nfc_queue_settings', 'aa_id_session_v1']));
    expect(left.keys.where(SensitiveData.isSensitive), isEmpty);
    expect(jsonEncode(left), isNot(contains('987654321')));
    expect(jsonEncode(left), isNot(contains('session=initial')));
    expect(jsonEncode(left), isNot(contains('daily')));
    expect(
      (await AccountStore().load()).single.cookie,
      serverSessionReference(accountId),
    );
  });

  test('an offline phone still removes what it kept', () async {
    await oldPhone();
    final backend = Backend()..offline = true;
    ServerSessions.active = backend.client();
    await SensitiveData.purge();
    final left = await const FlutterSecureStorage().readAll();
    expect(left.keys.where(SensitiveData.isSensitive), isEmpty);
    expect(jsonEncode(left), isNot(contains('session=initial')));
  });

  test('saving accounts never writes MIREA sessions to the phone', () async {
    final backend = Backend();
    ServerSessions.active = backend.client();
    await AccountStore().save([local]);
    expect(
      await const FlutterSecureStorage().read(key: 'pulse_accounts_v1'),
      isNull,
    );
    expect(backend.imports, 0);
  });
}
