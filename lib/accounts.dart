import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedAccount {
  const SavedAccount({
    required this.id,
    required this.label,
    required this.cookie,
  });
  final String id;
  final String label;
  final String cookie;

  Map<String, String> toJson() => {'id': id, 'label': label, 'cookie': cookie};

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
    id: json['id'] as String,
    label: json['label'] as String,
    cookie: json['cookie'] as String,
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
