import 'package:antiattendance/accounts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expiry is inclusive and survives storage', () {
    final expiry = DateTime.utc(2026, 10, 5, 12);
    final account = SavedAccount(
      id: '1',
      label: 'User',
      cookie: 'cookie',
      expiresAt: expiry,
    );
    final restored = SavedAccount.fromJson(account.toJson());
    expect(restored.expiresAt, expiry);
    expect(
      restored.isExpiredAt(expiry.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(restored.isExpiredAt(expiry), isTrue);
  });

  test('legacy sessions have unknown expiry and server expiry persists', () {
    final legacy = SavedAccount.fromJson({
      'id': '1',
      'label': 'User',
      'cookie': 'cookie',
    });
    expect(legacy.expiresAt, isNull);
    expect(legacy.isExpiredAt(DateTime.utc(2030)), isFalse);
    final expired = SavedAccount.fromJson({
      ...legacy.toJson(),
      'sessionExpired': true,
    });
    expect(
      SavedAccount.fromJson(expired.toJson()).isExpiredAt(DateTime.utc(2026)),
      isTrue,
    );
  });
}
