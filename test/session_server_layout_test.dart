import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/session_server_page.dart';
import 'package:antiattendance/session_server_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'server_sessions_test.dart' show snapshot;
import 'server_workspace_test.dart' show settleNetwork;

void main() {
  setUp(() {
    ServerSessions.active?.close();
    ServerSessions.active = null;
    SessionAutoSync.status.value = const SessionSyncStatus();
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    ServerSessions.active?.close();
    ServerSessions.active = null;
    SessionAutoSync.status.value = const SessionSyncStatus();
  });

  for (final mode in AppThemeMode.values) {
    testWidgets(
      '${mode.name} server overview stays quiet and settings fit large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ServerSessions.active = SessionServerClient('https://aa.ytc-srv.org')
          ..snapshot = snapshot();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(mode),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const SessionServerPage(),
          ),
        );
        await settleNetwork(tester);
        expect(find.text('aa.ytc-srv.org'), findsOneWidget);
        expect(tester.getTopLeft(find.text('aa.ytc-srv.org')).dx, 24);
        expect(find.byType(CampusTextField), findsNothing);
        expect(find.text('Disconnect server'), findsNothing);
        final scrollable = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Details'),
          150,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Details'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Accounts: 1'),
          150,
          scrollable: scrollable,
        );
        expect(find.text('Accounts: 1'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Connection settings'),
          150,
          scrollable: scrollable,
        );
        await tester.tap(find.text('Connection settings'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Disconnect server'),
          150,
          scrollable: scrollable,
        );
        expect(find.byType(CampusTextField), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'disconnected server has one address field and validates keyboard Go',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(AppThemeMode.dark),
          home: const SessionServerPage(),
        ),
      );
      await settleNetwork(tester);
      expect(find.byType(CampusTextField), findsOneWidget);
      expect(find.text('Connection settings'), findsNothing);
      await tester.enterText(find.byType(CampusTextField), 'not a url');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await settleNetwork(tester);
      expect(find.textContaining('Check the HTTP(S) address'), findsOneWidget);
      await tester.enterText(
        find.byType(CampusTextField),
        'https://aa.example',
      );
      await tester.pump();
      expect(find.textContaining('Check the HTTP(S) address'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
