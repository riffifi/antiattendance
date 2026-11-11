import 'dart:async';
import 'dart:convert';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_nfc_controller.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'server_contract_test.dart' show ownId, response, tokenGrant;

const cards = [
  {'account_id': ownId, 'own': true, 'pass_allowed': true, 'label': 'Alex'},
  {'account_id': 'shared', 'own': false, 'pass_allowed': true, 'label': 'Sam'},
];
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  late DateTime now;
  late SessionServerClient client;
  ServerNfcController? controller;
  var revoked = false;
  String? number;
  int gets = 0;
  setUp(() async {
    AaId.reset();
    FlutterSecureStorage.setMockInitialValues({});
    await AaId.acceptLogin(
      defaultAaIdUrl,
      AaIdSession.fromServer(tokenGrant()),
    );
    calls.clear();
    revoked = false;
    number = '9223372036854775807';
    gets = 0;
    now = DateTime.now();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nfcPassChannel, (call) async {
          calls.add(call);
          if (call.method == 'start' || call.method == 'status') {
            return {'armed': true, 'accountId': ownId, 'responded': true};
          }
          return null;
        });
    client = SessionServerClient(
      defaultSessionServerUrl,
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer access');
        expect(request.headers.containsKey('x-pulse-token'), isFalse);
        if (request.url.path == '/site/passes') {
          return response({'passes': cards});
        }
        gets++;
        if (revoked) return response({'detail': 'Pass not found'}, 404);
        return response({
          'account_id': request.url.pathSegments.last,
          'number': number,
        });
      }),
    );
  });
  tearDown(() {
    controller?.dispose();
    controller = null;
    client.close();
    AaId.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nfcPassChannel, null);
  });
  ServerNfcController create() =>
      controller = ServerNfcController(AaServerApi(client), now: () => now);

  test(
    'reads exact int64 strings on activation and never stores credentials',
    () async {
      final c = create();
      await c.refresh();
      expect(gets, 2);
      expect(c.enrolled, {ownId: true, 'shared': true});
      await c.activate();
      final start = calls.singleWhere((c) => c.method == 'start');
      final values = (start.arguments as Map)['passes'] as List;
      expect(values.single['number'], '9223372036854775807');
      expect(
        values.single['expiresAt'],
        now.add(const Duration(seconds: 90)).millisecondsSinceEpoch,
      );
      expect(c.running, isTrue);
      expect(
        (await const FlutterSecureStorage().readAll()).values.join(),
        isNot(contains(number!)),
      );
      await c.stop();
      expect(c.running, isFalse);
    },
  );

  test(
    'queue orders own card last and lease renewal does not restart it',
    () async {
      final c = create();
      await c.refresh();
      c.setSingle(false);
      c.choose('shared');
      await c.activate();
      final values =
          (calls.singleWhere((c) => c.method == 'start').arguments
                  as Map)['passes']
              as List;
      expect(values.map((v) => v['accountId']), ['shared', ownId]);
      now = now.add(const Duration(seconds: 21));
      await c.poll();
      expect(calls.where((c) => c.method == 'renew'), hasLength(1));
      expect(calls.where((c) => c.method == 'start'), hasLength(1));
      expect(c.running, isTrue);
    },
  );

  test('a revoked permission stops native presentation immediately', () async {
    final c = create();
    await c.refresh();
    await c.activate();
    revoked = true;
    now = now.add(const Duration(seconds: 21));
    await c.poll();
    expect(c.running, isFalse);
    expect(c.error, isA<SessionServerException>());
    expect(calls.last.method, 'stop');
    expect(calls.where((c) => c.method == 'renew'), isEmpty);
  });

  for (final invalid in [null, '0', '-1', '9223372036854775808', '1.5']) {
    test('invalid credential $invalid never reaches NFC', () async {
      number = invalid;
      final c = create();
      await c.refresh();
      await c.activate();
      expect(c.running, isFalse);
      expect(calls.where((c) => c.method == 'start'), isEmpty);
    });
  }

  test(
    'changed numbers stop the active queue instead of silently replacing it',
    () async {
      final c = create();
      await c.refresh();
      await c.activate();
      number = '456';
      now = now.add(const Duration(seconds: 21));
      await c.poll();
      expect(c.running, isFalse);
      expect(c.error, isA<FormatException>());
    },
  );

  test(
    'leaving during a delayed credential read cannot arm NFC later',
    () async {
      client.close();
      final pending = Completer<http.Response>();
      var delayRead = false;
      client = SessionServerClient(
        defaultSessionServerUrl,
        client: MockClient((request) async {
          if (request.url.path == '/site/passes') {
            return response({'passes': cards});
          }
          if (!delayRead) {
            return response({
              'account_id': request.url.pathSegments.last,
              'number': '123',
            });
          }
          return pending.future;
        }),
      );
      final c = create();
      await c.refresh();
      delayRead = true;
      final activation = c.activate();
      await Future<void>.delayed(Duration.zero);
      await c.stop();
      pending.complete(response({'account_id': ownId, 'number': '123'}));
      await activation;
      expect(c.running, isFalse);
      expect(calls.where((c) => c.method == 'start'), isEmpty);
    },
  );

  test(
    'JSON enrollment preserves a leading zero and never retries a mutation',
    () async {
      client.close();
      final seen = <http.Request>[];
      client = SessionServerClient(
        defaultSessionServerUrl,
        client: MockClient((request) async {
          seen.add(request);
          if (request.url.path.endsWith('/code')) {
            return response({'state': 'code_sent', 'retry_at': null});
          }
          return response({'detail': 'Incorrect verification code'}, 422);
        }),
      );
      final api = AaServerApi(client);
      await api.sendPassCode();
      await expectLater(
        api.issuePass('012345'),
        throwsA(
          isA<SessionServerException>().having(
            (e) => e.detail,
            'detail',
            'Incorrect verification code',
          ),
        ),
      );
      expect(seen.map((r) => r.url.path), [
        '/site/pass/code',
        '/site/pass/issue',
      ]);
      expect(jsonDecode(seen.last.body), {'code': '012345'});
      expect(() => api.issuePass('12345'), throwsFormatException);
      expect(seen, hasLength(2));
    },
  );
}
