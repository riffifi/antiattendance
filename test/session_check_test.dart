import 'dart:convert';
import 'dart:typed_data';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:antiattendance/session_check.dart';
import 'package:antiattendance/login_qr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nfc_pass_client/nfc_pass_client.dart';
import 'package:nfc_pass_client/src/protos/human_pass.pb.dart';

Uint8List frame(List<int> value, [int flag = 0]) => Uint8List(5 + value.length)
  ..[0] = flag
  ..buffer.asByteData().setUint32(1, value.length)
  ..setRange(5, 5 + value.length, value);

void main() {
  const account = SavedAccount(
    id: '1',
    label: 'User',
    cookie: '.AspNetCore.Cookies=test',
    sessionExpired: true,
  );
  NfcPassClient client(http.Client httpClient) => NfcPassClient(
    cookieProvider: () => account.cookie,
    endpoints: passClient(account).endpoints,
    httpClient: httpClient,
  );

  test('session check only requests a token and trusts server over saved status', () async {
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    final token =
        'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry})))}.sig';
    var requests = 0;
    final service = client(
      MockClient((request) async {
        requests++;
        expect(request.url.path, endsWith('/GetAccessTokenForDigitalPass'));
        expect(request.headers['cookie'], account.cookie);
        return http.Response.bytes(
          [
            ...frame(
              GetAccessTokenForDigitalPassResponse(jwt: token).writeToBuffer(),
            ),
            ...frame(ascii.encode('grpc-status: 0\r\n'), 0x80),
          ],
          200,
          headers: {'content-type': 'application/grpc-web+proto'},
        );
      }),
    );
    addTearDown(service.httpClient.close);
    final result = await checkSession(account, client: service);
    expect(result.state, SessionCheckState.valid);
    expect(result.tokenExpiresAt!.millisecondsSinceEpoch, expiry * 1000);
    expect(requests, 1);
    expect(account.expiresAt, isNull);
  });

  for (final status in [401, 403, 500]) {
    test(
      'HTTP $status classifies expired, forbidden, and service failures',
      () async {
        final service = client(
          MockClient((_) async => http.Response('', status)),
        );
        addTearDown(service.httpClient.close);
        expect(
          (await checkSession(account, client: service)).state,
          status == 401
              ? SessionCheckState.expired
              : status == 403
              ? SessionCheckState.forbidden
              : SessionCheckState.unavailable,
        );
      },
    );
  }
  test('login redirect is an expired session', () async {
    final service = client(
      MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://pulse.mirea.ru/api/auth/login'},
        ),
      ),
    );
    addTearDown(service.httpClient.close);
    expect(
      (await checkSession(account, client: service)).state,
      SessionCheckState.expired,
    );
  });
  test('gRPC unauthenticated is an expired session', () async {
    final service = client(
      MockClient(
        (_) async => http.Response.bytes(
          frame(ascii.encode('grpc-status: 16\r\n'), 0x80),
          200,
          headers: {'content-type': 'application/grpc-web+proto'},
        ),
      ),
    );
    addTearDown(service.httpClient.close);
    expect(
      (await checkSession(account, client: service)).state,
      SessionCheckState.expired,
    );
  });
  test('network failures do not claim the session expired', () async {
    final service = client(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    addTearDown(service.httpClient.close);
    expect(
      (await checkSession(account, client: service)).state,
      SessionCheckState.unavailable,
    );
  });
  test('HTML instead of a token is an invalid response', () async {
    final service = client(
      MockClient((_) async => http.Response('<html>login</html>', 200)),
    );
    addTearDown(service.httpClient.close);
    expect(
      (await checkSession(account, client: service)).state,
      SessionCheckState.invalidResponse,
    );
  });
  test('QR accepts only the university login challenge', () {
    const valid =
        'https://sso.mirea.ru/realms/mirea/qr-code-auth/scan?qrToken=test&qr_code_originated=true';
    expect(mireaLoginQr(valid), valid);
    for (final value in [
      null,
      1,
      '',
      valid.replaceFirst('https:', 'http:'),
      valid.replaceFirst('sso.mirea.ru', 'evil.example'),
      valid.replaceFirst('sso.mirea.ru', 'user@sso.mirea.ru'),
      valid.replaceFirst('/scan', '/approve'),
      valid.replaceFirst('qrToken=test', 'qrToken='),
      valid.replaceFirst('sso.mirea.ru', 'sso.mirea.ru:8443'),
    ]) {
      expect(mireaLoginQr(value), isNull);
    }
  });
}
