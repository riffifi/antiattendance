import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/pulse_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const qr =
    'https://pulse.mirea.ru/lessons/visiting-logs/self-approve?token=abc';

class MemoryAccountStore extends AccountStore {
  MemoryAccountStore(this.accounts);
  final List<SavedAccount> accounts;

  @override
  Future<List<SavedAccount>> load() async => accounts;

  @override
  Future<void> save(List<SavedAccount> value) async {
    accounts
      ..clear()
      ..addAll(value);
  }
}

class RecordingApi extends PulseApi {
  final calls = <String>[];

  @override
  Future<ApprovalResult> approve(String token, String cookie) async {
    calls.add('$token:$cookie');
    return const ApprovalResult(
      ApprovalState.approved,
      'Присутствие подтверждено',
    );
  }
}

void main() {
  testWidgets('shows a simple scan and account list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(store: MemoryAccountStore([]))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Посещаемость'), findsOneWidget);
    expect(find.text('Сканировать QR'), findsOneWidget);
    expect(find.text('Аккаунты'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a scan immediately submits for selected accounts', (
    tester,
  ) async {
    final api = RecordingApi();
    final store = MemoryAccountStore([
      const SavedAccount(id: '1', label: 'Аня', cookie: 'one'),
      const SavedAccount(id: '2', label: 'Борис', cookie: 'two'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(store: store, api: api, scanQr: (_) async => qr),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сканировать QR'));
    await tester.pumpAndSettle();
    expect(api.calls, containsAll(['abc:one', 'abc:two']));
    expect(find.text('Присутствие подтверждено'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid pasted link cannot submit a previous QR', (
    tester,
  ) async {
    final api = RecordingApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          store: MemoryAccountStore([
            const SavedAccount(id: '1', label: 'Аня', cookie: 'one'),
          ]),
          api: api,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вставить ссылку'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://example.com/?token=bad',
    );
    await tester.tap(find.text('Отправить'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
