import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/session_expiry.dart';
import 'package:flutter_test/flutter_test.dart';

String jwt(Object payload) =>
    'eyJhbGciOiJSUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.signature';

void main() {
  final expiry = DateTime.utc(2030, 1, 1);
  test('current and legacy authentication cookies expose expiry without companion cookies', () {
    for (final name in [
      '.AspNetCore.Cookies',
      '.AspNetCore.CookiesC1',
      '__Host-PulseSession',
      '__Secure-session_id',
      '.AspNetCore.Identity.Application',
    ]) {
      expect(
        sessionCookieExpiry(
          '$name=opaque; __ddg1_=gateway; _ga=analytics',
          cookieExpiries: {
            name: expiry.millisecondsSinceEpoch,
            '__ddg1_': 1,
            '_ga': 2,
          },
        ),
        expiry,
      );
    }
  });
  test('JWT session expiry can be recovered from existing saved accounts', () {
    final header =
        '__Host-PulseSession=${jwt({'exp': expiry.millisecondsSinceEpoch ~/ 1000})}';
    expect(sessionCookieExpiry(header), expiry);
    expect(
      SavedAccount.fromJson({'id': 'a', 'label': 'Alice', 'cookie': header})
          .expiresAt,
      expiry,
    );
  });
  test('access/pass tokens and opaque browser sessions do not invent an expiry', () {
    expect(
      sessionCookieExpiry(
        'access_token=${jwt({'exp': 1})}; pass-token=${jwt({'exp': 2})}; session=opaque',
      ),
      isNull,
    );
    expect(sessionCookieExpiry('session=not.valid.json'), isNull);
    expect(sessionCookieExpiry('session=${jwt({'exp': 'wrong'})}'), isNull);
    expect(sessionCookieExpiry('session=${jwt({'exp': -1})}'), isNull);
  });
  test(
    'browser Max-Age uses seconds and wins over Expires regardless of order',
    () {
      final now = DateTime.utc(2026, 10, 14, 15);
      for (final attrs in [
        'Max-Age=3600; Expires=Tue, 01 Jan 2030 00:00:00 GMT',
        'Expires=Tue, 01 Jan 2030 00:00:00 GMT; Max-Age=3600',
      ]) {
        final metadata = expiryMetadataFromCookieInfo([
          'session=opaque; $attrs; HttpOnly',
        ], now: now);
        expect(
          metadata['session'],
          now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        );
      }
      final metadata = expiryMetadataFromCookieInfo([
        'session=opaque; Expires=Tue, 01 Jan 2030 15:30:00 GMT',
      ]);
      expect(
        metadata['session'],
        DateTime.utc(2030, 1, 1, 15, 30).millisecondsSinceEpoch,
      );
    },
  );
  test(
    'embedded expiry is not extended by a longer browser persistence date',
    () {
      expect(
        sessionCookieExpiry(
          'session=${jwt({'exp': expiry.millisecondsSinceEpoch ~/ 1000})}',
          cookieExpiries: {
            'session': expiry
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch,
          },
        ),
        expiry,
      );
    },
  );
}
