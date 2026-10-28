import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nfc_pass_client/nfc_pass_client.dart';

import 'accounts.dart';
import 'server_sessions.dart';

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

/// Pass numbers are never stored on the phone. They live on the session server,
/// which hands them out only while the owner allows it, and are kept in memory.
class NfcPassStore {
  NfcPassStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  Future<String?> number(SavedAccount account) async {
    final remoteId = serverAccountId(account.cookie);
    if (remoteId == null) return null;
    await ServerSessions.initialize();
    return ServerSessions.active?.passNumber(remoteId);
  }

  Future<void> save(SavedAccount account, int number) async {
    if (number <= 0) throw ArgumentError.value(number);
    final remoteId = serverAccountId(account.cookie);
    if (remoteId == null) {
      throw StateError('Passes are kept only on the session server.');
    }
    final client = ServerSessions.requireClient();
    await client.publishPass(
      remoteId,
      number.toString(),
      expectedVersion: client.passVersion(remoteId),
    );
    await client.fetch();
    ServerSessions.notify();
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

/// Passes are never sent from phone to phone.
Future<Map<String, String>> transferPassNumbers(
  List<SavedAccount> accounts,
) async => const {};
