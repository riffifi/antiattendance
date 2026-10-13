import 'dart:convert';
import 'dart:async';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/nfc_pass.dart';
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
  const renewed = SavedAccount(
    id: 'local',
    label: 'Owner',
    cookie: 'session=renewed',
  );

  test('initial sessions and passes upload automatically and unchanged data is not sent again', () async {
    final accounts = AccountStore();
    final passes = NfcPassStore();
    await accounts.save([local]);
    await passes.save(local, 12345);
    final backend = Backend();
    ServerSessions.active = backend.client();
    await SessionAutoSync.sync();
    expect(backend.imports, 1);
    expect(backend.passWrites, 1);
    expect(backend.number, '12345');
    expect(ServerSessions.active!.importedIds['local'], accountId);
    await SessionAutoSync.sync();
    expect(backend.imports, 1);
    expect(backend.passWrites, 1);
    expect(
      (await accounts.load()).single.cookie,
      serverSessionReference(accountId),
    );
  });

  test('new enrollments upload immediately and offline pass updates use the original revision', () async {
    final accounts = AccountStore();
    final passes = NfcPassStore();
    await accounts.save([local]);
    await passes.save(local, 111);
    final backend = Backend();
    ServerSessions.active = backend.client();
    await SessionAutoSync.sync();
    backend.sharedPass('222');
    await SessionAutoSync.sync();
    expect(ServerSessions.active!.passNumber(accountId), '222');
    await passes.save(local, 333);
    await SessionAutoSync.sync();
    expect(backend.number, '333');
    expect(backend.passVersions.last, 2);
    backend.offline = true;
    await passes.save(local, 555);
    await SessionAutoSync.sync();
    backend.sharedPass('444');
    backend.offline = false;
    await SessionAutoSync.sync();
    expect(backend.passVersions.last, 3);
    expect(backend.number, '444');
    final writes = backend.passWrites;
    await SessionAutoSync.sync();
    expect(backend.passWrites, writes);
  });

  test('offline login retries, survives client restart, and cannot replace a newer session', () async {
    final accounts = AccountStore();
    await accounts.save([local]);
    final backend = Backend();
    ServerSessions.active = backend.client();
    await SessionAutoSync.sync();
    backend.offline = true;
    await accounts.save([renewed]);
    await SessionAutoSync.sync();
    expect(SessionAutoSync.status.value.failed, isTrue);
    backend.sharedSession();
    backend.offline = false;
    ServerSessions.active!.close();
    ServerSessions.active = backend.client();
    await SessionAutoSync.sync();
    expect(backend.importVersions.last, 1);
    expect(backend.account!['session_version'], 2);
    final imports = backend.imports;
    await SessionAutoSync.sync();
    expect(backend.imports, imports);
  });

  test('a failed account upload does not prevent other accounts from being attempted', () async {
    await AccountStore().save([
      local,
      const SavedAccount(
        id: 'second',
        label: 'Second',
        cookie: 'session=second',
      ),
    ]);
    final backend = Backend();
    ServerSessions.active = SessionServerClient(
      'http://localhost:8080',
      client: MockClient((request) async {
        if (request.url.path == '/api/accounts/import' &&
            request.body.contains('session=initial')) {
          return http.Response('{}', 422);
        }
        return backend.handle(request);
      }),
    );
    await SessionAutoSync.sync();
    expect(backend.account!['label'], 'Second');
    expect(SessionAutoSync.status.value.pending, 1);
  });

  test(
    'removed shared accounts are not resurrected by retained local sessions',
    () async {
      await AccountStore().save([local]);
      final backend = Backend();
      ServerSessions.active = backend.client();
      await SessionAutoSync.sync();
      backend.account = null;
      backend.number = null;
      backend.cursor++;
      await SessionAutoSync.sync();
      expect(backend.account, isNull);
      expect(backend.imports, 1);
    },
  );
  test('a second local enrollment during an upload follows its own acknowledged revision', () async {
    final accounts = AccountStore();
    final passes = NfcPassStore();
    await accounts.save([local]);
    await passes.save(local, 111);
    final backend = Backend();
    ServerSessions.active = backend.client();
    await SessionAutoSync.sync();
    final gate = Completer<void>();
    backend.passGate = gate;
    backend.passStarted = Completer<void>();
    await passes.save(local, 333);
    await backend.passStarted!.future;
    final savingNewer = passes.save(local, 444);
    // The second local write completes before waiting on the in-flight journal.
    for (var i = 0; i < 30 && await passes.number(local) != '444'; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(await passes.number(local), '444');
    gate.complete();
    await savingNewer;
    await SessionAutoSync.sync();
    expect(backend.number, '444');
    expect(backend.passVersions.last, 2);
  });
}
