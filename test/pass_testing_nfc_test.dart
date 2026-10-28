import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:antiattendance/nfc_pass_page.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';

import 'pass_enrollment_test.dart' show EnrollmentClient;
import 'pass_testing_client_test.dart' show id, approvalSnapshot;

void main() {
  testWidgets(
    'native NFC testing is capped at the grant deadline and stops when testing is disabled',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({});
      final server = SessionServerClient(
        'https://example.com',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path == '/api/accounts'
                  ? approvalSnapshot()
                  : {
                      'expires_at':
                          DateTime.now()
                              .add(const Duration(minutes: 5))
                              .millisecondsSinceEpoch /
                          1000,
                    },
            ),
            200,
          ),
        ),
      );
      ServerSessions.active = server;
      addTearDown(() {
        server.close();
        ServerSessions.active = null;
      });
      await tester.runAsync(() => server.enablePassTesting('test-password'));
      server.snapshot = approvalSnapshot();
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
      final pass = (activation!['passes'] as List).single as Map;
      expect(
        pass['expiresAt'],
        server.passTestingUntil!.millisecondsSinceEpoch,
      );
      await server.disablePassTesting();
      // The queue's poll timer was started in real time by runAsync.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(armed, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
