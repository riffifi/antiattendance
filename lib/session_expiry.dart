import 'dart:convert';
import 'dart:io' show HttpDate;

/// Authentication cookies only: gateway, analytics, CSRF and short-lived pass
/// access tokens do not describe the lifetime of the saved login session.
bool isSessionExpiryCookie(String name) {
  final normalized = name.toLowerCase().replaceFirst(
    RegExp(r'^__(host|secure)-'),
    '',
  );
  return RegExp(r'^\.aspnetcore\.cookies(?:c[1-9][0-9]*)?$')
          .hasMatch(normalized) ||
      normalized == '.aspnetcore.identity.application' ||
      RegExp(r'^(?:pulse[._-]?)?session(?:[._-]?id)?$').hasMatch(normalized);
}

DateTime? sessionCookieExpiry(
  String header, {
  Map<String, int?> cookieExpiries = const {},
}) {
  final dates = <DateTime>[];
  for (final item in header.split(';')) {
    final separator = item.indexOf('=');
    if (separator <= 0) continue;
    final name = item.substring(0, separator).trim();
    if (!isSessionExpiryCookie(name)) continue;
    final metadata = cookieExpiries[name];
    if (metadata != null && metadata > 0) {
      try {
        dates.add(DateTime.fromMillisecondsSinceEpoch(metadata, isUtc: true));
      } catch (_) {
        /* Invalid metadata is not an expiry. */
      }
    }
    final value = item.substring(separator + 1).trim();
    if (value.length > 65536) continue;
    final parts = value.split('.');
    if (parts.length != 3) continue;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final expiry = payload is Map ? payload['exp'] : null;
      if (expiry is int && expiry > 0 && expiry < 8640000000000) {
        dates.add(
          DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true),
        );
      }
    } catch (_) {
      /* Encrypted/opaque cookies have no readable embedded expiry. */
    }
  }
  dates.sort();
  return dates.firstOrNull;
}

/// Android's profile CookieManager returns Set-Cookie attributes where its
/// GET_COOKIE_INFO feature is available. Max-Age is in seconds, not milliseconds.
Map<String, int?> expiryMetadataFromCookieInfo(
  List<String> infos, {
  DateTime? now,
}) {
  final result = <String, int?>{};
  for (final info in infos) {
    final parts = info.split(';');
    final separator = parts.first.indexOf('=');
    if (separator <= 0) continue;
    final name = parts.first.substring(0, separator).trim();
    int? expires, maxAge;
    for (final part in parts.skip(1)) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final key = part.substring(0, separator).trim().toLowerCase();
      final value = part.substring(separator + 1).trim();
      if (key == 'max-age') maxAge = int.tryParse(value);
      if (key == 'expires') {
        try {
          expires = HttpDate.parse(value).millisecondsSinceEpoch;
        } catch (_) {
          /* Ignore malformed dates. */
        }
      }
    }
    result[name] = maxAge == null
        ? expires
        : (now ?? DateTime.now()).millisecondsSinceEpoch + maxAge * 1000;
  }
  return result;
}
