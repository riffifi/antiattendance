import 'dart:async';
import 'dart:convert';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_nfc_page.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'server_contract_test.dart' show ownId, response, tokenGrant;
import 'server_workspace_test.dart' show settleNetwork;
import 'server_nfc_test.dart' show cards;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    AaId.reset();
    FlutterSecureStorage.setMockInitialValues({});
    await AaId.acceptLogin(
      defaultAaIdUrl,
      AaIdSession.fromServer(tokenGrant()),
    );
  });
  tearDown(AaId.reset);

  Future<void> enrollment(
    WidgetTester tester,
    SessionServerClient client,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ServerPassEnrollmentPage(
                    api: AaServerApi(client),
                    accountId: ownId,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('owner enters leading-zero code; no automatic code request', (
    tester,
  ) async {
    final seen = <http.Request>[];
    final client = SessionServerClient(
      defaultSessionServerUrl,
      client: MockClient((r) async {
        seen.add(r);
        if (r.method == 'GET') {
          return response({'account_id': ownId, 'number': null});
        }
        return response({'account_id': ownId, 'number': '123'});
      }),
    );
    addTearDown(client.close);
    await enrollment(tester, client);
    expect(seen, isEmpty);
    await tester.enterText(find.byType(CampusTextField), '012345');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('issue-pass')));
    await settleNetwork(tester);
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(seen.map((r) => r.url.path), [
      '/site/passes/$ownId',
      '/site/passes/$ownId/issue',
    ]);
    expect(jsonDecode(seen.last.body), {'code': '012345'});
  });

  testWidgets('uncertain issue is read back, never automatically repeated', (
    tester,
  ) async {
    var issued = false, posts = 0, reads = 0;
    final client = SessionServerClient(
      defaultSessionServerUrl,
      client: MockClient((r) async {
        if (r.method == 'GET') {
          reads++;
          return response({
            'account_id': ownId,
            'number': issued ? '456' : '123',
          });
        }
        posts++;
        issued = true;
        return response({'detail': 'Temporary upstream error'}, 503);
      }),
    );
    addTearDown(client.close);
    await enrollment(tester, client);
    await tester.enterText(find.byType(CampusTextField), '012345');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('issue-pass')));
    await settleNetwork(tester);
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(reads, 2);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('incorrect code stays editable with the server explanation', (
    tester,
  ) async {
    var posts = 0;
    final client = SessionServerClient(
      defaultSessionServerUrl,
      client: MockClient((r) async {
        if (r.method == 'GET') {
          return response({'account_id': ownId, 'number': '123'});
        }
        posts++;
        return response({'detail': 'Incorrect verification code'}, 422);
      }),
    );
    addTearDown(client.close);
    await enrollment(tester, client);
    await tester.enterText(find.byType(CampusTextField), '012345');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('issue-pass')));
    await settleNetwork(tester);
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.text('Incorrect verification code'), findsOneWidget);
    expect(
      tester.widget<CampusTextField>(find.byType(CampusTextField)).enabled,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shared pass enrollment targets its owner for code and issuance',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final seen = <http.Request>[];
      var issued = false;
      final client = SessionServerClient(
        defaultSessionServerUrl,
        client: MockClient((r) async {
          seen.add(r);
          if (r.url.path == '/site/passes') {
            return response({
              'passes': [
                ...cards,
                {
                  'account_id': 'disabled',
                  'label': 'Disabled',
                  'own': false,
                  'pass_allowed': false,
                },
              ],
            });
          }
          if (r.url.path.endsWith('/code')) {
            return response({'state': 'code_sent', 'retry_at': null});
          }
          if (r.method == 'POST') issued = true;
          return response({
            'account_id': r.method == 'GET'
                ? r.url.pathSegments.last
                : 'shared',
            'number': r.method == 'GET'
                ? (r.url.pathSegments.last == ownId
                      ? '123'
                      : issued
                      ? '456'
                      : null)
                : '456',
          });
        }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ServerNfcPassPage(api: AaServerApi(client)),
        ),
      );
      await settleNetwork(tester);
      expect(find.byKey(const ValueKey('enroll-pass-disabled')), findsNothing);
      expect(find.byKey(const ValueKey('enroll-pass-$ownId')), findsNothing);
      final enroll = find.byKey(const ValueKey('enroll-pass-shared'));
      await tester.ensureVisible(enroll);
      await tester.pumpAndSettle();
      await tester.tap(enroll);
      await settleNetwork(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ServerPassEnrollmentPage), findsOneWidget);
      expect(
        tester
            .widget<ServerPassEnrollmentPage>(
              find.byType(ServerPassEnrollmentPage),
            )
            .accountId,
        'shared',
      );
      expect(find.text('Sam'), findsOneWidget);
      await tester.tap(find.text('Get code'));
      await settleNetwork(tester);
      await tester.enterText(find.byType(CampusTextField), '012345');
      await tester.pump();
      final issue = find.byKey(const ValueKey('issue-pass'));
      await tester.ensureVisible(issue);
      await tester.tap(issue);
      await settleNetwork(tester);
      await tester.pumpAndSettle();
      final posts = seen.where((r) => r.method == 'POST').toList();
      expect(posts.map((r) => r.url.path), [
        '/site/passes/shared/code',
        '/site/passes/shared/issue',
      ]);
      expect(jsonDecode(posts.last.body), {'code': '012345'});
      expect(find.byType(ServerPassEnrollmentPage), findsNothing);
      expect(find.byKey(const ValueKey('enroll-pass-shared')), findsNothing);
      expect(seen.where((r) => r.url.path == '/site/passes').length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Back cannot abandon an in-flight pass issuance', (tester) async {
    final pending = Completer<http.Response>();
    var posts = 0;
    final client = SessionServerClient(
      defaultSessionServerUrl,
      client: MockClient((r) async {
        if (r.method == 'GET') {
          return response({'account_id': ownId, 'number': null});
        }
        posts++;
        return pending.future;
      }),
    );
    addTearDown(client.close);
    await enrollment(tester, client);
    await tester.enterText(find.byType(CampusTextField), '012345');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('issue-pass')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(posts, 1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ServerPassEnrollmentPage), findsOneWidget);
    pending.complete(response({'account_id': ownId, 'number': '456'}));
    await settleNetwork(tester);
    expect(find.byType(ServerPassEnrollmentPage), findsNothing);
    expect(posts, 1);
  });

  for (final mode in AppThemeMode.values) {
    testWidgets('NFC controls fit 320dp with double text in ${mode.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = SessionServerClient(
        defaultSessionServerUrl,
        client: MockClient(
          (r) async => r.url.path == '/site/passes'
              ? response({'passes': cards})
              : response({
                  'account_id': r.url.pathSegments.last,
                  'number': null,
                }),
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(mode),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: ServerNfcPassPage(api: AaServerApi(client)),
        ),
      );
      await settleNetwork(tester);
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      final enrollment = find.byKey(const ValueKey('enroll-pass-$ownId'));
      await tester.scrollUntilVisible(
        enrollment,
        160,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(enrollment, findsOneWidget);
      final row = find.ancestor(
        of: enrollment,
        matching: find.byType(CampusListItem),
      );
      expect(
        (tester.getCenter(enrollment).dy - tester.getCenter(row).dy).abs(),
        lessThan(1),
      );
      await tester.scrollUntilVisible(
        find.text('Queue'),
        -160,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Queue'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
