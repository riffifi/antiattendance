import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nfc_pass_client/nfc_pass_client.dart';

import 'accounts.dart';
import 'server_sessions.dart';
import 'session_server_sync.dart';

const nfcPassChannel = MethodChannel('antiattendance/nfc_pass');

NfcPassClient passClient(SavedAccount account) => NfcPassClient(
  cookieProvider: () => serverAccountId(account.cookie) == null
      ? account.cookie
      : 'server=managed',
  httpClient: serverAccountId(account.cookie) == null
      ? null
      : ServerRpcClient(
          ServerSessions.requireClient(),
          serverAccountId(account.cookie)!,
        ),
  endpoints: NfcPassEndpoints(
    accessTokenUrl: Uri.https(
      'pulse.mirea.ru',
      '/rtu.pulse_app.LongTimeTokenService/GetAccessTokenForDigitalPass',
    ),
    sendVerificationCodeUrl: Uri.https(
      'pulse.mirea.ru',
      '/rtu_tc.rtu_attend.humanpass.HumanPassService/SendVerificationCode',
    ),
    getDigitalPassUrl: Uri.https(
      'pulse.mirea.ru',
      '/rtu_tc.rtu_attend.humanpass.HumanPassService/GetDigitalPass',
    ),
  ),
);

DateTime passTokenExpiry(String jwt) {
  final parts = jwt.split('.');
  if (parts.length != 3) throw const FormatException('Invalid pass token.');
  final payload = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
  );
  final exp = payload is Map ? payload['exp'] : null;
  if (exp is! int || exp <= 0 || exp > 253402300799) {
    throw const FormatException('Pass token has no valid expiration.');
  }
  final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
  if (!expiry.isAfter(DateTime.now())) {
    throw const FormatException('Pass token expired. Sign in again.');
  }
  return expiry;
}

List<SavedAccount> orderPassQueue(
  List<SavedAccount> accounts,
  String? ownAccountId,
) => [
  ...accounts.where((account) => account.id != ownAccountId),
  ...accounts.where((account) => account.id == ownAccountId),
];

class NfcPassStore {
  NfcPassStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  String _fingerprint(SavedAccount account) =>
      sha256.convert(utf8.encode(account.cookie)).toString();

  Future<String?> number(SavedAccount account) async {
    final remoteId = serverAccountId(account.cookie);
    if (remoteId != null) {
      await ServerSessions.initialize();
      final server = ServerSessions.active;
      return server?.passNumber(remoteId);
    }
    final raw = await _storage.read(key: 'nfc_pass_${account.id}');
    if (raw == null) return null;
    final record = jsonDecode(raw) as Map<String, dynamic>;
    if (record['session'] != _fingerprint(account)) return null;
    final number = record['number'] as String;
    final value = int.tryParse(number);
    return value != null && value > 0 ? number : null;
  }

  Future<void> save(SavedAccount account, int number) async {
    if (number <= 0) throw ArgumentError.value(number);
    final remoteId = serverAccountId(account.cookie);
    if (remoteId != null) {
      await SessionAutoSync.passChanged(account, number.toString());
      await SessionAutoSync.sync();
      return;
    }
    await _storage.write(
      key: 'nfc_pass_${account.id}',
      value: jsonEncode({
        'number': number.toString(),
        'session': _fingerprint(account),
      }),
    );
    await SessionAutoSync.passChanged(account, number.toString());
  }

  Future<void> remove(String accountId) =>
      _storage.delete(key: 'nfc_pass_$accountId');

  Future<Map<String, dynamic>> settings() async {
    final raw = await _storage.read(key: 'nfc_queue_settings');
    return raw == null ? {} : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveSettings(
    int seconds,
    String? ownAccountId, [
    Iterable<String>? selectedIds,
    bool single = false,
    String? singleAccountId,
  ]) => _storage.write(
    key: 'nfc_queue_settings',
    value: jsonEncode({
      'seconds': seconds,
      'ownAccountId': ownAccountId,
      if (selectedIds != null) 'selectedIds': selectedIds.toList(),
      if (single || singleAccountId != null)
        'mode': single ? 'single' : 'queue',
      'singleAccountId': ?singleAccountId,
    }),
  );
}

Future<Map<String, String>> transferPassNumbers(
  List<SavedAccount> accounts,
) async {
  final store = NfcPassStore();
  final result = <String, String>{};
  for (final account in accounts) {
    final number = await store.number(account);
    if (number != null) result[account.id] = number;
  }
  return result;
}
