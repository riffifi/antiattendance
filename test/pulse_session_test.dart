import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/pulse_api.dart';
import 'package:antiattendance/pulse_session.dart';
import 'package:antiattendance/session_check.dart';
import 'package:nfc_pass_client/nfc_pass_client.dart';

Uint8List frame(List<int> body, [int flag = 0]) => Uint8List(5 + body.length)
  ..[0] = flag
  ..buffer.asByteData().setUint32(1, body.length)
  ..setRange(5, 5 + body.length, body);
List<int> field(int id, List<int> value) => [
  id * 8 + 2,
  value.length,
  ...value,
];
List<int> response(List<int> message, {String status = '0'}) => [
  ...frame(message),
  ...frame(ascii.encode('grpc-status: $status\r\n'), 128),
];
void main() {
  final authorized = field(1, field(1, field(1, utf8.encode('test-user-id'))));
  final anonymous = field(
    2,
    field(1, utf8.encode('https://pulse.mirea.ru/api/auth/login')),
  );
  test('current identity API proves authentication without digital-pass permissions', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), pulseProfileUrl);
      expect(request.followRedirects, isFalse);
      expect(
        request.headers['cookie'],
        '__Host-PulseSession=new; __ddg1_=gateway',
      );
      expect(request.headers['x-requested-with'], 'XMLHttpRequest');
      expect(
        utf8.decode(request.bodyBytes, allowMalformed: true),
        contains('https://pulse.mirea.ru'),
      );
      return http.Response.bytes(
        response(authorized),
        200,
        headers: {'content-type': 'application/grpc-web+proto'},
      );
    });
    addTearDown(client.close);
    final result = await checkSession(
      const SavedAccount(
        id: '1',
        label: 'User',
        cookie: '__Host-PulseSession=new; __ddg1_=gateway',
        sessionExpired: true,
      ),
      profileClient: client,
    );
    expect(result.state, SessionCheckState.valid);
    expect(result.tokenExpiresAt, isNull);
  });
  test(
    'notAuthorized response is an expired session, not an empty success',
    () {
      expect(
        decodePulseSession(Uint8List.fromList(response(anonymous))),
        PulseSessionState.expired,
      );
      expect(
        decodePulseSession(Uint8List.fromList(response([18, 0]))),
        PulseSessionState.expired,
      );
    },
  );
  test('empty authorized object does not prove a signed-in identity', () {
    expect(
      decodePulseSession(Uint8List.fromList(response([10, 0]))),
      PulseSessionState.invalidResponse,
    );
  });
  test('HTTP 403 and gateway HTML do not expire saved accounts', () async {
    for (final reply in [
      http.Response('Forbidden', 403),
      http.Response('<html>Gateway challenge</html>', 200),
    ]) {
      final client = MockClient((_) async => reply);
      addTearDown(client.close);
      final state = await probePulseSession(
        '.AspNetCore.Cookies=session',
        client: client,
      );
      expect(state, isNot(PulseSessionState.expired));
      expect(state, isNot(PulseSessionState.valid));
    }
  });
  test(
    'network errors and unrelated redirects keep session state unknown',
    () async {
      for (final failed in [false, true]) {
        final client = MockClient((_) async {
          if (failed) throw http.ClientException('offline');
          return http.Response('', 307, headers: {'location': '/maintenance'});
        });
        addTearDown(client.close);
        expect(
          await probePulseSession(
            '.AspNetCore.Cookies=session',
            client: client,
          ),
          PulseSessionState.unavailable,
        );
      }
    },
  );
  test(
    'malformed trailers and truncated payloads cannot look authenticated',
    () {
      for (final value in [
        Uint8List.fromList([0, 0, 0, 0, 10, 10]),
        frame(authorized),
        Uint8List.fromList(response(authorized, status: 'unknown')),
        Uint8List.fromList(response([...authorized, ...anonymous])),
      ]) {
        expect(decodePulseSession(value), PulseSessionState.invalidResponse);
      }
      expect(
        decodePulseSession(Uint8List.fromList(response([], status: '16'))),
        PulseSessionState.expired,
      );
      expect(
        decodePulseSession(Uint8List.fromList(response([], status: '7'))),
        PulseSessionState.forbidden,
      );
    },
  );
  test(
    'new cookie names and companion gateway cookies survive pass transport',
    () {
      final cookie = pulseSessionCookie({
        '__Host-PulseSession': 'token',
        '__ddg1_': 'gateway',
      });
      expect(nfcSessionCookieHeader(cookie), cookie);
      expect(cookie, contains('__Host-PulseSession=token'));
      expect(cookie, contains('__ddg1_=gateway'));
      expect(
        pulseSessionCookie({
          '.AspNetCore.Cookies': 'chunks-1',
          '.AspNetCore.CookiesC1': 'abc',
          '__ddg1_': 'gateway',
        }),
        '.AspNetCore.Cookies=chunks-1; .AspNetCore.CookiesC1=abc; __ddg1_=gateway',
      );
    },
  );
  test(
    'gateway-only and unfinished SSO cookies are not session candidates',
    () {
      expect(
        () => pulseSessionCookie({'__ddg1_': 'gateway'}),
        throwsFormatException,
      );
      expect(
        () => pulseSessionCookie({'.AspNetCore.Correlation.x': 'state'}),
        throwsFormatException,
      );
      expect(
        () => pulseSessionCookie({
          '.AspNetCore.Cookies': 'chunks-2',
          '.AspNetCore.CookiesC1': 'abc',
        }),
        throwsFormatException,
      );
    },
  );
  test('generic cookie validation still rejects header injection and duplicate names', () {
    expect(
      isValidPulseCookieHeader('__Host-Session=abc\r\nX-Evil: yes'),
      isFalse,
    );
    expect(isValidPulseCookieHeader('session=abc; session=other'), isFalse);
    expect(isValidPulseCookieHeader('other=value; malformed'), isFalse);
    expect(isValidPulseCookieHeader('session=valid'), isTrue);
  });
  test(
    'attendance access denied is not mislabeled as expired authentication',
    () async {
      final client = MockClient((_) async => http.Response('', 403));
      final api = PulseApi(client: client);
      addTearDown(api.close);
      await expectLater(
        api.approve('qr', '.AspNetCore.Cookies=valid'),
        throwsA(
          isA<PulseApiException>().having(
            (e) => e.sessionExpired,
            'sessionExpired',
            false,
          ),
        ),
      );
    },
  );
}
