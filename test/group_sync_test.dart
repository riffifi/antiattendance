import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/expressive.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/session_server_sync.dart';
import 'package:antiattendance/settings_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';

const remoteId = '12345678-1234-1234-1234-123456789abc';

class MemoryAccounts extends AccountStore {
  @override
  Future<List<SavedAccount>> load() async => const [
    SavedAccount(
      id: 'a',
      label: 'Alice',
      cookie: 'a',
      groupId: 42,
      groupName: 'Group A',
    ),
    SavedAccount(
      id: 'b',
      label: 'Bob',
      cookie: 'b',
      groupId: 43,
      groupName: 'Group B',
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ServerSessions.active = null;
  });
  tearDown(() async {
    await SessionAutoSync.sync();
    ServerSessions.active?.close();
    ServerSessions.active = null;
  });

  test(
    'filtered requests reject old servers and never adopt another group',
    () async {
      final calls = <Uri>[];
      final client = SessionServerClient(
        'http://localhost',
        groupId: 42,
        client: MockClient((request) async {
          calls.add(request.url);
          return http.Response(
            jsonEncode({
              'protocol': 2,
              'sync': 'automatic',
              'cursor': 0,
              'accounts': [],
              'passes': [],
            }),
            200,
          );
        }),
      );
      await expectLater(client.fetch(), throwsFormatException);
      expect(calls.single.queryParameters['group_id'], '42');
      expect(client.accounts, isEmpty);
      client.close();
    },
  );

  test(
    'a remote group edit retries offline without uploading a session or a pass',
    () async {
      var offline = false;
      var writes = 0;
      final row = <String, dynamic>{
        'id': remoteId,
        'label': 'Alice',
        'group_id': 42,
        'group_name': 'Group A',
        'state': 'valid',
        'version': 1,
        'session_version': 1,
        'pass_version': 0,
      };
      final client = SessionServerClient(
        'http://localhost',
        client: MockClient((request) async {
          if (offline) return http.Response('{}', 503);
          if (request.url.path == '/api/accounts') {
            final group = int.tryParse(
              request.url.queryParameters['group_id'] ?? '',
            );
            return http.Response(
              jsonEncode({
                'protocol': 2,
                'sync': 'automatic',
                'cursor': row['version'],
                'group_filter': group,
                'accounts': [
                  if (group == null || group == row['group_id']) row,
                ],
                'passes': [],
              }),
              200,
            );
          }
          expect(request.url.path, '/api/accounts/$remoteId/group');
          writes++;
          final body = jsonDecode(request.body) as Map;
          expect(body['expected_version'], row['version']);
          row['group_id'] = body['group_id'];
          row['group_name'] = body['group_name'];
          row['version'] = (row['version'] as int) + 1;
          return http.Response(jsonEncode(row), 200);
        }),
      );
      ServerSessions.active = client;
      await client.fetch();
      offline = true;
      await AccountStore().save([
        SavedAccount(
          id: 'server_$remoteId',
          label: 'Alice',
          cookie: serverSessionReference(remoteId),
          groupId: 43,
          groupName: 'Group B',
        ),
      ]);
      await SessionAutoSync.sync();
      expect(writes, 0);
      offline = false;
      await SessionAutoSync.sync();
      expect(writes, 1);
      expect(client.accounts.single['group_id'], 43);
      expect(row['session_version'], 1);
      expect(row['pass_version'], 0);
      await SessionAutoSync.sync();
      expect(writes, 1);
    },
  );

  testWidgets('attendance group filter scopes both rows and selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(store: MemoryAccounts()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppPassPicker).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group A').last);
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Selected: 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('My group can be chosen and cleared in settings', (tester) async {
    final settings = AppSettingsStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: SettingsPage(
          store: settings,
          language: null,
          onLanguageChanged: (_) {},
          accounts: await MemoryAccounts().load(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('All groups'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group B'));
    await tester.pumpAndSettle();
    expect((await settings.loadMyGroup())?.id, 43);
    await tester.tap(find.text('Group B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All groups'));
    await tester.pumpAndSettle();
    expect(await settings.loadMyGroup(), isNull);
  });
}
