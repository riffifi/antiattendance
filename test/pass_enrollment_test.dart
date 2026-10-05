import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:antiattendance/nfc_pass_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nfc_pass_client/nfc_pass_client.dart';

class EnrollmentClient extends NfcPassClient {
  EnrollmentClient({
    this.tokenError,
    this.codeError,
    this.wrongFirstCode = false,
    this.shortFirstToken = false,
  }) : super(
         cookieProvider: () => '.AspNetCore.Cookies=test',
         endpoints: NfcPassEndpoints(
           accessTokenUrl: Uri.https('pulse.mirea.ru', '/token'),
           sendVerificationCodeUrl: Uri.https('pulse.mirea.ru', '/code'),
           getDigitalPassUrl: Uri.https('pulse.mirea.ru', '/pass'),
         ),
         httpClient: MockClient(
           (_) async => throw StateError('Unexpected HTTP'),
         ),
       );
  final Object? tokenError;
  final Object? codeError;
  final bool wrongFirstCode;
  final bool shortFirstToken;
  int tokenCalls = 0;
  int codeCalls = 0;
  int passCalls = 0;

  @override
  Future<String> getAccessTokenForDigitalPass({String? sessionCookie}) async {
    tokenCalls++;
    if (tokenError != null) throw tokenError!;
    final exp =
        DateTime.now()
            .add(
              shortFirstToken && tokenCalls == 1
                  ? const Duration(seconds: 4)
                  : const Duration(hours: 1),
            )
            .millisecondsSinceEpoch ~/
        1000;
    return 'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': exp})))}.sig';
  }

  @override
  Future<NfcVerificationResult> sendVerificationCode(
    String bearerToken, {
    String? sessionCookie,
  }) async {
    codeCalls++;
    if (codeError != null) throw codeError!;
    return const NfcVerificationCodeSent();
  }

  @override
  Future<int> getDigitalPass({
    required String bearerToken,
    required String sixDigitCode,
    required String deviceName,
    String? sessionCookie,
  }) async {
    passCalls++;
    if (wrongFirstCode && passCalls == 1) {
      throw const NfcVerificationException(NfcVerificationFailure.wrongCode);
    }
    expect(sixDigitCode, '123456');
    return 42;
  }
}

void main() {
  const account = SavedAccount(
    id: 'a',
    label: 'Alice',
    cookie: '.AspNetCore.Cookies=test',
  );
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nfcPassChannel, (_) async => null);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nfcPassChannel, null);
  });
  Future<void> showPage(
    WidgetTester tester,
    EnrollmentClient client, {
    Future<void> Function(SavedAccount)? onExpired,
    Future<void> Function(SavedAccount)? onReauth,
  }) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: NfcPassPage(
            accounts: const [account],
            clientFactory: (_) => client,
            onSessionExpired: onExpired,
            onReauth: onReauth,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enroll'));
    await tester.tap(find.text('Enroll'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets(
    'bulk pass enrollment saves successes and pauses on cancellation',
    (tester) async {
      const bob = SavedAccount(
        id: 'b',
        label: 'Bob',
        cookie: '.AspNetCore.Cookies=bob',
      );
      final aliceClient = EnrollmentClient();
      final bobClient = EnrollmentClient();
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NfcPassPage(
              accounts: const [account, bob],
              clientFactory: (a) =>
                  a.id == account.id ? aliceClient : bobClient,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enroll passes together'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byType(CampusTextField).last, '123456');
      await tester.pump();
      await tester.tap(find.text('Enroll').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await NfcPassStore().number(account), '42');
      expect(await NfcPassStore().number(bob), isNull);
      expect(aliceClient.passCalls, 1);
      expect(bobClient.passCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('expired enrollment session offers sign-in and persists expiry', (
    tester,
  ) async {
    final client = EnrollmentClient(
      tokenError: const NfcPassTransportException(
        'unauthenticated',
        grpcStatus: 16,
      ),
    );
    var expired = false;
    var reauth = false;
    await showPage(
      tester,
      client,
      onExpired: (_) async {
        expired = true;
      },
      onReauth: (_) async {
        reauth = true;
      },
    );
    expect(expired, isTrue);
    expect(find.text('Session expired. Sign in again.'), findsOneWidget);
    expect(client.codeCalls, 0);
    await tester.tap(find.text('Sign in again'));
    await tester.pumpAndSettle();
    expect(reauth, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('unreachable service does not ask for another login', (
    tester,
  ) async {
    final client = EnrollmentClient(
      tokenError: const NfcPassUnreachableException('pulse.mirea.ru'),
    );
    var expired = false;
    await showPage(
      tester,
      client,
      onExpired: (_) async {
        expired = true;
      },
    );
    expect(
      find.text(
        'Pass service unreachable. Check your connection and try later.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sign in again'), findsNothing);
    expect(expired, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('pass bearer failure does not falsely expire a valid session', (
    tester,
  ) async {
    final client = EnrollmentClient(
      codeError: const NfcPassTransportException(
        'bearer rejected',
        grpcStatus: 16,
      ),
    );
    var expired = false;
    await showPage(
      tester,
      client,
      onExpired: (_) async {
        expired = true;
      },
    );
    expect(
      find.text(
        'Pass token rejected. Enroll the pass again; your session is valid.',
      ),
      findsOneWidget,
    );
    expect(expired, isFalse);
    expect(client.tokenCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('nearly expired pass token is refreshed before issuance', (
    tester,
  ) async {
    final client = EnrollmentClient(shortFirstToken: true);
    await showPage(tester, client);
    await tester.enterText(find.byType(CampusTextField).last, '123456');
    await tester.pump();
    await tester.tap(find.text('Enroll').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(client.tokenCalls, 2);
    expect(client.codeCalls, 1);
    expect(await NfcPassStore().number(account), '42');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'wrong code can be corrected without sending another verification code',
    (tester) async {
      final client = EnrollmentClient(wrongFirstCode: true);
      await showPage(tester, client);
      Future<void> enterCode() async {
        await tester.enterText(find.byType(CampusTextField).last, '123456');
        await tester.pump();
        await tester.tap(find.text('Enroll').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
      }

      await enterCode();
      expect(
        find.text(
          'Incorrect verification code. Check the code and enter it again.',
        ),
        findsOneWidget,
      );
      await enterCode();
      expect(client.passCalls, 2);
      expect(client.codeCalls, 1);
      expect(await NfcPassStore().number(account), '42');
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
