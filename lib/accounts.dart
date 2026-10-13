import 'dart:convert';

import 'server_sessions.dart';
import 'session_server_sync.dart';
import 'app_settings.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedAccount {
  const SavedAccount({
    required this.id,
    required this.label,
    required this.cookie,
    this.expiresAt,
    this.sessionExpired = false,
    this.groupId,
    this.groupName,
    this.transferredPassNumber,
  });
  final String id;
  final String label;
  final String cookie;
  final DateTime? expiresAt;
  final bool sessionExpired;

  bool isExpiredAt(DateTime now) =>
      sessionExpired || (expiresAt != null && !now.isBefore(expiresAt!));

  final int? groupId;
  final String? groupName;

  // Incoming transfer only; pass numbers are persisted by NfcPassStore.
  final int? transferredPassNumber;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'cookie': cookie,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    if (sessionExpired) 'sessionExpired': true,
    if (groupId != null) 'groupId': groupId,
    if (groupName != null) 'groupName': groupName,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
    id: json['id'] as String,
    label: json['label'] as String,
    cookie: json['cookie'] as String,
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    sessionExpired: json['sessionExpired'] == true,
    groupId: json['groupId'] as int?,
    groupName: json['groupName'] as String?,
  );
}

class AccountStore {
  AccountStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'pulse_accounts_v1';

  Future<List<SavedAccount>> loadLocal() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((value) => SavedAccount.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<List<SavedAccount>> load() async {
    final group = await AppSettingsStore().loadMyGroup();
    final local = (await loadLocal())
        .where((a) => group == null || a.groupId == group.id)
        .toList();
    await ServerSessions.initialize();
    final server = ServerSessions.active;
    if (server == null) return local;
    try {
      await SessionAutoSync.sync();
    } catch (_) {
      /* Keep cached metadata offline. */
    }
    final remote = server.accounts
        .map(
          (row) => SavedAccount(
            id: 'server_${row['id']}',
            label: row['label'] as String,
            cookie: serverSessionReference(row['id'] as String),
            sessionExpired: row['state'] == 'expired',
            expiresAt: row['expires_at'] is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    ((row['expires_at'] as num) * 1000).round(),
                    isUtc: true,
                  )
                : null,
            groupId: row['group_id'] as int?,
            groupName: row['group_name'] as String?,
          ),
        )
        .toList();
    return [
      ...local.where(
        (a) =>
            serverAccountId(a.cookie) == null &&
            !server.importedIds.containsKey(a.id),
      ),
      ...remote,
    ];
  }

  Future<void> save(List<SavedAccount> accounts) async {
    final previous = await loadLocal();
    final myGroup = await AppSettingsStore().loadMyGroup();
    accounts = accounts
        .map(
          (a) =>
              myGroup != null &&
                  a.groupId == null &&
                  serverAccountId(a.cookie) == null &&
                  !previous.any((old) => old.id == a.id)
              ? SavedAccount(
                  id: a.id,
                  label: a.label,
                  cookie: a.cookie,
                  expiresAt: a.expiresAt,
                  sessionExpired: a.sessionExpired,
                  groupId: myGroup.id,
                  groupName: myGroup.name,
                  transferredPassNumber: a.transferredPassNumber,
                )
              : a,
        )
        .toList();
    await SessionAutoSync.groupChanges(accounts);
    // Server metadata is authoritative; local edits never replace its cookies.
    final mapped =
        ServerSessions.active?.importedIds.keys.toSet() ?? <String>{};
    final retained = previous.where(
      (a) =>
          mapped.contains(a.id) || myGroup != null && a.groupId != myGroup.id,
    );
    final local = accounts
        .where((a) => serverAccountId(a.cookie) == null)
        .toList();
    final ids = local.map((a) => a.id).toSet();
    local.addAll(retained.where((a) => !ids.contains(a.id)));
    await _storage.write(
      key: _key,
      value: jsonEncode(local.map((a) => a.toJson()).toList()),
    );
    await SessionAutoSync.accountChanges(previous, local);
  }
}

int? transferredPassNumber(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(raw)) {
    throw const FormatException('Invalid NFC pass number.');
  }
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw const FormatException('Invalid NFC pass number.');
  }
  return value;
}
