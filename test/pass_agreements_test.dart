import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/nfc_pass_page.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:flutter/foundation.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'pass_enrollment_test.dart' show EnrollmentClient;

import 'server_sessions_test.dart' show id, snapshot;

Map<String, dynamic> approval(String status) {
  final result = snapshot();
  result['pass_agreements_required'] = true;
  result['pass_access_expires_at'] =
      DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch /
      1000;
  (result['accounts'] as List).first['pass_access'] = status;
  return result;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() {
    ServerSessions.active?.close();
    ServerSessions.active = null;
  });

  test('approval and a current lease are required; grant-only pass numbers are never cached', () {
    final server = SessionServerClient('https://agreements.example');
    addTearDown(server.close);
    server.snapshot = approval('pending');
    expect(server.passNumber(id), isNull);
    expect(server.canUsePass(id), isFalse);
    server.snapshot = approval('approved');
    expect(server.canUsePass(id), isTrue);
    expect(server.passNumber(id), '12345');
    expect((server.cacheSnapshot['passes'] as List).first['number'], isNull);
    expect(server.testingExpiryFor(id), server.passAccessUntil);
    server.snapshot['pass_access_expires_at'] =
        DateTime.now()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch /
        1000;
    expect(server.passNumber(id), isNull);
    server.snapshot = approval('denied');
    expect(server.canUsePass(id), isFalse);
  });

  test('private app identity survives restart per server and is separate from Telegram handoff', () async {
    final keys = <String>[];
    http.Client transport() => MockClient((request) async {
      keys.add(request.headers['x-pass-client']!);
      if (request.url.path.endsWith('/pass-request')) {
        return http.Response(
          jsonEncode({
            'url': 'https://t.me/example_bot?start=access_opaque-handoff',
          }),
          200,
        );
      }
      return http.Response(jsonEncode(approval('pending')), 200);
    });
    final first = SessionServerClient(
      'https://agreements.example',
      client: transport(),
    );
    await first.fetch();
    final url = await first.requestPassAccess(id);
    expect(url.host, 't.me');
    expect(keys.first.length, 43);
    expect(url.toString(), isNot(contains(keys.first)));
    first.close();
    final restored = SessionServerClient(
      'https://agreements.example',
      client: transport(),
    );
    addTearDown(restored.close);
    await restored.fetch();
    expect(keys.toSet(), hasLength(1));
    final other = SessionServerClient(
      'https://other.example',
      client: transport(),
    );
    addTearDown(other.close);
    await other.fetch();
    expect(keys.last, isNot(keys.first));
    expect(jsonEncode(restored.cacheSnapshot), isNot(contains(keys.first)));
  });

  test(
    'Telegram handoff rejects foreign hosts and embedded credentials',
    () async {
      for (final url in [
        'https://evil.example/bot',
        'http://t.me/bot',
        'https://secret@t.me/bot',
      ]) {
        final server = SessionServerClient(
          'https://agreements.example',
          client: MockClient(
            (_) async => http.Response(jsonEncode({'url': url}), 200),
          ),
        );
        await expectLater(server.requestPassAccess(id), throwsFormatException);
        server.close();
      }
    },
  );

  testWidgets(
    'native activation is capped by the approval lease and revocation stops it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var current = approval('approved');
      final server = SessionServerClient(
        'https://agreements.example',
        client: MockClient(
          (_) async => http.Response(jsonEncode(current), 200),
        ),
      )..snapshot = current;
      ServerSessions.active = server;
      final account = SavedAccount(
        id: 'server_$id',
        label: 'Owner',
        cookie: serverSessionReference(id),
      );
      await NfcPassStore().saveSettings(
        60,
        null,
        [account.id],
        true,
        account.id,
      );
      var armed = false;
      Map<String, dynamic>? activation;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(nfcPassChannel, (call) async {
        if (call.method == 'start') {
          activation = Map<String, dynamic>.from(call.arguments as Map);
          armed = true;
        }
        if (call.method == 'stop') armed = false;
        return {'armed': armed};
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(nfcPassChannel, null),
      );
      final page = GlobalKey<NfcPassPageState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NfcPassPage(
              key: page,
              requireAgreements: true,
              accounts: [account],
              clientFactory: (_) => EnrollmentClient(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => page.currentState!.startFromWidget());
      await tester.pumpAndSettle();
      expect(armed, isTrue);
      expect(
        ((activation!['passes'] as List).single as Map)['expiresAt'],
        server.passAccessUntil!.millisecondsSinceEpoch,
      );
      current = approval('denied');
      server.snapshot = current;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 450)),
      );
      await tester.pumpAndSettle();
      expect(armed, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'pending approval shows its state and cannot enroll; local Legacy passes cannot bypass approvals',
    (tester) async {
      final server = SessionServerClient('https://agreements.example')
        ..snapshot = approval('pending');
      ServerSessions.active = server;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NfcPassPage(
              requireAgreements: true,
              accounts: [
                SavedAccount(
                  id: 'server_$id',
                  label: 'Owner',
                  cookie: serverSessionReference(id),
                ),
                const SavedAccount(
                  id: 'local',
                  label: 'Legacy owner',
                  cookie: 'local-session',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Waiting for the owner’s decision in Telegram.'),
        250,
      );
      expect(
        find.text('Waiting for the owner’s decision in Telegram.'),
        findsOneWidget,
      );
      // A local Legacy pass is not on the list at all.
      expect(find.text('Legacy owner'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
