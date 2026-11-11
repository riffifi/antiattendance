import 'dart:async';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_profile_page.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'server_contract_test.dart' show response, tokenGrant;
import 'server_workspace_test.dart' show settleNetwork;

void main() {
  setUp(() async {
    AaId.reset();
    FlutterSecureStorage.setMockInitialValues({});
    await AaId.acceptLogin(
      defaultAaIdUrl,
      AaIdSession.fromServer(tokenGrant()),
    );
    AaId.httpClient = () =>
        MockClient((r) async => response({'username': 'alex'}));
  });
  tearDown(AaId.reset);

  Future<void> open(WidgetTester tester, SessionServerClient client) async {
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ServerProfilePage(api: AaServerApi(client)),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await settleNetwork(tester);
  }

  SessionServerClient client(
    Future<http.Response> Function(http.Request)? handler,
  ) => SessionServerClient(
    defaultSessionServerUrl,
    client: MockClient(
      handler ??
          (r) async =>
              response({'label': 'Alex', 'connected': true, 'account': true}),
    ),
  );

  testWidgets(
    'invalid profile values show inline errors and editing clears them',
    (tester) async {
      var writes = 0;
      await open(
        tester,
        client((r) async {
          if (r.method == 'PUT') writes++;
          return response({
            'label': 'Alex',
            'connected': true,
            'account': true,
          });
        }),
      );
      await tester.tap(find.text('Name and username'));
      await tester.pumpAndSettle();
      final fields = find.byType(CampusTextField);
      await tester.enterText(fields.first, '');
      await tester.enterText(fields.last, '1bad');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a name between 1 and 60 characters.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Use 3–24 Latin letters, digits or underscores, starting with a letter.',
        ),
        findsOneWidget,
      );
      expect(writes, 0);
      await tester.enterText(fields.first, 'Alex New');
      await tester.enterText(fields.last, 'alex');
      await tester.pump();
      expect(
        find.text('Enter a name between 1 and 60 characters.'),
        findsNothing,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleNetwork(tester);
      expect(writes, 1);
      expect(find.text('Alex New'), findsWidgets);
    },
  );

  testWidgets(
    'Back collapses commands before offering to discard profile edits',
    (tester) async {
      await open(tester, client(null));
      await tester.tap(find.text('Name and username'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CampusTextField).first, 'Draft');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Expand app bar'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsNothing);
      expect(find.byType(ServerProfilePage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CampusTextField>(find.byType(CampusTextField).first)
            .controller!
            .text,
        'Draft',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
    },
  );

  testWidgets(
    'failed profile load offers retry without an empty editable profile',
    (tester) async {
      var reads = 0;
      await open(
        tester,
        client((r) async {
          reads++;
          if (reads == 1) return response({'detail': 'Unavailable'}, 503);
          return response({
            'label': 'Alex',
            'connected': true,
            'account': true,
          });
        }),
      );
      expect(find.text('Name and username'), findsNothing);
      expect(find.byType(CampusTextField), findsNothing);
      await tester.tap(find.text('Retry'));
      await settleNetwork(tester);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Name and username'), findsOneWidget);
      expect(reads, 2);
    },
  );

  testWidgets(
    'Back waits for a profile save and successful save needs no discard prompt',
    (tester) async {
      final pending = Completer<http.Response>();
      var writes = 0;
      await open(
        tester,
        client((r) async {
          if (r.method == 'PUT') {
            writes++;
            return pending.future;
          }
          return response({
            'label': 'Alex',
            'connected': true,
            'account': true,
          });
        }),
      );
      await tester.tap(find.text('Name and username'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CampusTextField).first, 'Alex New');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Save'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(writes, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(ServerProfilePage), findsOneWidget);
      expect(find.text('Unsaved changes'), findsNothing);
      pending.complete(response({'label': 'Alex New'}));
      await settleNetwork(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
    },
  );
}
