import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alice = SavedAccount(id: 'a', label: 'Alice', cookie: 'session-a');
  const bob = SavedAccount(id: 'b', label: 'Bob', cookie: 'session-b');
  const self = SavedAccount(id: 'me', label: 'Me', cookie: 'session-me');

  test('own pass is last and remaining order is stable', () {
    final accounts = [alice, self, bob];
    expect(orderPassQueue(accounts, 'me'), [alice, bob, self]);
    expect(orderPassQueue(accounts, null), accounts);
    expect(orderPassQueue(accounts, 'unknown'), accounts);
    expect(accounts, [alice, self, bob]);
  });

  test('rejects missing or expired token expiry', () {
    String token(Object? exp) =>
        'e30.${base64Url.encode(utf8.encode(jsonEncode({'exp': exp})))}.signature';
    final future =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    expect(
      passTokenExpiry(token(future)).millisecondsSinceEpoch,
      future * 1000,
    );
    expect(() => passTokenExpiry(token(1)), throwsFormatException);
    expect(() => passTokenExpiry(token(null)), throwsFormatException);
    expect(() => passTokenExpiry(token('123')), throwsFormatException);
    expect(() => passTokenExpiry('opaque'), throwsFormatException);
  });

  test('pass stays bound to enrolled session and is removable', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = NfcPassStore();
    await store.save(alice, 9223372036854775807);
    expect(await store.number(alice), '9223372036854775807');
    expect(await store.number(bob), isNull);
    expect(
      await store.number(
        const SavedAccount(id: 'a', label: 'Alice', cookie: 'replacement'),
      ),
      isNull,
    );
    await store.remove(alice.id);
    expect(await store.number(alice), isNull);
  });

  test('queue preferences persist', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = NfcPassStore();
    await store.saveSettings(75, 'me');
    expect(await store.settings(), {'seconds': 75, 'ownAccountId': 'me'});
  });

  test(
    'an explicitly empty selection stays empty for widget launches',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = NfcPassStore();
      await store.saveSettings(90, 'me', ['a', 'me']);
      expect((await store.settings())['selectedIds'], ['a', 'me']);
      await store.saveSettings(90, 'me', []);
      expect((await store.settings())['selectedIds'], isEmpty);
    },
  );
}
