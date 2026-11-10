import 'dart:convert';

import 'package:antiattendance/aa_id.dart';
import 'package:antiattendance/aa_id_page.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/app_tutorial.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/server_api.dart';
import 'package:antiattendance/server_profile_page.dart';
import 'package:antiattendance/server_schedule_page.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:brockmann/brockmann.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'server_contract_test.dart' show response, tokenGrant;
import 'server_workspace_test.dart' show settleNetwork;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    AaId.reset();
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(AaId.reset);

  testWidgets(
    'header actions align with the trailing gutter at both text sizes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 430.0]) {
        tester.view.physicalSize = Size(width, 850);
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: CampusScaffold(
                appBar: CampusAppBar(
                  title: const Text('How to use'),
                  automaticallyImplyLeading: false,
                  actions: [CampusTextAction(label: 'Skip', onPressed: () {})],
                ),
                body: const SizedBox(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.bySemanticsLabel('Skip')).right,
            closeTo(width - 24, 1),
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('first-run tutorial can be skipped and stays dismissed', (
    tester,
  ) async {
    final store = AppSettingsStore();
    Widget app() => MaterialApp(
      theme: AppTheme.light,
      home: AaIdGate(tutorialStore: store, child: const Text('Home')),
    );
    await tester.pumpWidget(app());
    await settleNetwork(tester);
    expect(find.byType(AppTutorial), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Skip'));
    await settleNetwork(tester);
    expect(await store.tutorialSeen(), isTrue);
    expect(find.byType(AaIdSignInPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(app());
    await settleNetwork(tester);
    expect(find.byType(AppTutorial), findsNothing);
  });

  testWidgets('tutorial pages remain scrollable with double text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var finished = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppThemeMode.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AppTutorial(
          onComplete: () async {
            finished++;
          },
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(finished, 1);
  });

  testWidgets('schedule refresh keeps the selected day and Today is explicit', (
    tester,
  ) async {
    final key = GlobalKey<ServerSchedulePageState>();
    final client = SessionServerClient(
      'https://aa.example',
      client: MockClient(
        (r) async => response({
          'group_name': 'Group A',
          'days': [
            {
              'date': '2026-11-10',
              'today': true,
              'lessons': [
                {'subject': 'Today class', 'start': '09:00', 'end': '10:00'},
              ],
            },
            {
              'date': '2026-11-11',
              'lessons': [
                {
                  'subject': 'Other day class',
                  'start': '11:00',
                  'end': '12:00',
                },
              ],
            },
          ],
        }),
      ),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ServerSchedulePage(
            key: key,
            api: AaServerApi(client),
            active: true,
          ),
        ),
      ),
    );
    await settleNetwork(tester);
    tester.widget<BrockmannPicker>(find.byType(BrockmannPicker)).onChanged!(1);
    await tester.pumpAndSettle();
    expect(find.text('Other day class'), findsOneWidget);
    final pending = key.currentState!.refresh();
    await settleNetwork(tester);
    await pending;
    expect(find.text('Other day class'), findsOneWidget);
    final today = key.currentState!.refresh(goToToday: true);
    await settleNetwork(tester);
    await today;
    expect(find.text('Today class'), findsOneWidget);
  });

  testWidgets(
    'profile edits only the changed name and keeps device access available',
    (tester) async {
      await AaId.acceptLogin(
        defaultAaIdUrl,
        AaIdSession.fromServer(tokenGrant()),
      );
      final identityPaths = <String>[];
      AaId.httpClient = () => MockClient((r) async {
        identityPaths.add(r.url.path);
        return response({'username': 'alex', 'group_name': 'Group A'});
      });
      final bodies = <Map<String, dynamic>>[];
      final client = SessionServerClient(
        defaultSessionServerUrl,
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
          }
          return response({
            'label': 'Alex Morgan',
            'account': true,
            'connected': true,
          });
        }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ServerProfilePage(api: AaServerApi(client)),
        ),
      );
      await settleNetwork(tester);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
      await tester.tap(find.text('Name and username'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CampusTextField).first, 'Alex New');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Save'));
      await settleNetwork(tester);
      expect(bodies, [
        {'label': 'Alex New'},
      ]);
      expect(identityPaths, hasLength(1));
      expect(find.text('Alex New'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'profile retry refreshes claims without repeating a saved username',
    (tester) async {
      await AaId.acceptLogin(
        defaultAaIdUrl,
        AaIdSession.fromServer(tokenGrant()),
      );
      var usernameWrites = 0, refreshes = 0;
      AaId.httpClient = () => MockClient((r) async {
        if (r.method == 'PUT') {
          usernameWrites++;
          return response({'username': 'alex_new'});
        }
        if (r.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          if (refreshes == 1) {
            return response({'message': 'Temporary failure'}, 503);
          }
          return response(tokenGrant());
        }
        return response({'username': 'alex', 'group_name': 'Group A'});
      });
      final client = SessionServerClient(
        defaultSessionServerUrl,
        client: MockClient(
          (r) async =>
              response({'label': 'Alex', 'account': true, 'connected': true}),
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ServerProfilePage(api: AaServerApi(client)),
        ),
      );
      await settleNetwork(tester);
      await tester.tap(find.text('Name and username'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CampusTextField).last, 'alex_new');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Save'));
      await settleNetwork(tester);
      expect(usernameWrites, 1);
      expect(refreshes, 1);
      await tester.tap(find.bySemanticsLabel('Save'));
      await settleNetwork(tester);
      expect(usernameWrites, 1);
      expect(refreshes, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
