String nfcSessionCookieHeader(String cookie) {
  if (cookie.isEmpty || cookie.length > 65536) {
    throw const FormatException('Invalid session cookie.');
  }
  final cookies = <String, String>{};
  final header = cookie.contains(';') ||
      RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+=").hasMatch(cookie);
  final parts = header ? cookie.split(';') : ['.AspNetCore.Cookies=$cookie'];
  for (final part in parts) {
    final normalized = part.trim();
    final separator = normalized.indexOf('=');
    if (separator < 1) throw const FormatException('Invalid session cookie.');
    final name = normalized.substring(0, separator);
    final value = normalized.substring(separator + 1);
    if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name) ||
        cookies.containsKey(name) ||
        value.isEmpty ||
        value.codeUnits.any(
          (byte) =>
              byte < 0x21 ||
              byte > 0x7e ||
              const [0x22, 0x2c, 0x3b, 0x5c].contains(byte),
        ) ||
        part.contains('\r') ||
        part.contains('\n')) {
      throw const FormatException('Invalid session cookie.');
    }
    cookies[name] = value;
  }
  final base = cookies['.AspNetCore.Cookies'];
  if (base == null) {
    if (cookies.keys.any((name) => name.startsWith('.AspNetCore.CookiesC')))
      throw const FormatException('Missing session cookie.');
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
  final chunked = base.startsWith('chunks-');
  if (chunked && !RegExp(r'^chunks-[1-9][0-9]*$').hasMatch(base)) {
    throw const FormatException('Invalid chunked session cookie.');
  }
  final count = chunked ? int.tryParse(base.substring('chunks-'.length)) : 0;
  if (count == null ||
      count < 0 ||
      count > 64 ||
      cookies.keys
              .where((name) =>
                  name == '.AspNetCore.Cookies' ||
                  name.startsWith('.AspNetCore.CookiesC'))
              .length !=
          count + 1) {
    throw const FormatException('Incomplete session cookie.');
  }
  final entries = ['.AspNetCore.Cookies=$base'];
  for (var index = 1; index <= count; index++) {
    final name = '.AspNetCore.CookiesC$index';
    final chunk = cookies[name];
    if (chunk == null) {
      throw const FormatException('Incomplete session cookie.');
    }
    entries.add('$name=$chunk');
  }
  entries.addAll(cookies.entries
      .where((e) =>
          e.key != '.AspNetCore.Cookies' &&
          !e.key.startsWith('.AspNetCore.CookiesC'))
      .map((e) => '${e.key}=${e.value}'));
  return entries.join('; ');
}
