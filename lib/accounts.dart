import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedAccount {
  const SavedAccount({
    required this.id,
    required this.label,
    required this.cookie,
    this.groupId,
    this.groupName,
  });
  final String id;
  final String label;
  final String cookie;
  final int? groupId;
  final String? groupName;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'cookie': cookie,
    if (groupId != null) 'groupId': groupId,
    if (groupName != null) 'groupName': groupName,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
    id: json['id'] as String,
    label: json['label'] as String,
    cookie: json['cookie'] as String,
    groupId: json['groupId'] as int?,
    groupName: json['groupName'] as String?,
  );
}

class AccountStore {
  AccountStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'pulse_accounts_v1';

  Future<List<SavedAccount>> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((value) => SavedAccount.fromJson(value as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<SavedAccount> accounts) async {
    await _storage.write(
      key: _key,
      value: jsonEncode(accounts.map((account) => account.toJson()).toList()),
    );
  }
}
