import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'accounts.dart';
import 'server_sessions.dart';
import 'session_server_sync.dart';

/// Older versions kept MIREA sessions, pass numbers, the pass testing password
/// and a sync journal with pass numbers on the phone. This version keeps none
/// of them: accounts are handed to the session server once, then removed.
abstract final class SensitiveData {
  static const _storage = FlutterSecureStorage();

  static bool isSensitive(String key) =>
      key == 'pulse_accounts_v1' ||
      key == 'session_server_mappings_v1' ||
      key.startsWith('nfc_pass_') ||
      key.startsWith('session_sync_') ||
      key.startsWith('pass_testing_');

  static Future<void> purge({FlutterSecureStorage storage = _storage}) async {
    final legacy = (await AccountStore(
      storage: storage,
    ).loadLocal()).where((account) => serverAccountId(account.cookie) == null);
    if (legacy.isNotEmpty) {
      await ServerSessions.initialize();
      if (ServerSessions.active != null) {
        try {
          // The last upload of accounts that only this phone had.
          await SessionAutoSync.sync().timeout(const Duration(seconds: 30));
        } catch (_) {
          /* Removed below either way: the phone must not keep them. */
        }
      }
    }
    final keys = (await storage.readAll()).keys.where(isSensitive).toList();
    for (final key in keys) {
      await storage.delete(key: key);
    }
    if (ServerSessions.active != null) await ServerSessions.saveSnapshot();
  }
}
