import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:antiattendance/settings_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

const local = SavedAccount(
  id: 'local-owner',
  label: 'Legacy owner',
  cookie: 'local-test-session',
);

void main() {
  setUp(() {
    ServerSessions.active?.close();
    ServerSessions.active = null;
    FlutterSecureStorage.setMockInitialValues({
      'pulse_accounts_v1': jsonEncode([local.toJson()]),
    });
  });

  test(
    'server view excludes local sessions while the legacy store retains them',
    () async {
      expect(await ServerAccountStore().load(), isEmpty);
      expect((await LegacyAccountStore().load()).single.cookie, local.cookie);
      await LegacyAccountStore().save([]);
      expect(await LegacyAccountStore().load(), isEmpty);
    },
  );

  testWidgets(
    'Settings opens the local legacy view without exposing local accounts on the main screen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomePage(
            startAtSelector: true,
            legacyMode: false,
            store: ServerAccountStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
      await tester.pumpAndSettle();
      expect(find.text(local.label), findsNothing);
      expect(find.text('Receive'), findsNothing);
      await tester.tap(find.text('INDEX'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-3')));
      await tester.pumpAndSettle();
      expect(find.text('Debug menu'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Legacy'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Legacy'));
      await tester.pumpAndSettle();
      expect(find.text(local.label), findsOneWidget);
      final home = tester.widget<HomePage>(find.byType(HomePage).last);
      expect(home.legacyMode, isTrue);
      expect(home.store, isA<LegacyAccountStore>());
      expect(find.byType(CampusNavigation), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Legacy'), findsOneWidget);
      expect(find.text(local.label), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
