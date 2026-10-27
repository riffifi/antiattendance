import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:antiattendance/nfc_pass_page.dart';
import 'package:antiattendance/server_sessions.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pass_enrollment_test.dart' show enrollmentServer, aliceId;

class _Store extends AccountStore {
  _Store(this.accounts);
  List<SavedAccount> accounts;
  @override
  Future<List<SavedAccount>> load() async => accounts;
  @override
  Future<void> save(List<SavedAccount> value) async {
    accounts = value;
  }
}

void main() {
  const account = SavedAccount(
    id: 'alice',
    label: 'Alice',
    cookie: 'test-session',
    groupId: 42,
    groupName: 'Group 42',
  );
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('renaming keeps the session and group', (tester) async {
    final store = _Store([account]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(store: store),
      ),
    );
    await tester.pumpAndSettle();
    final menu = find.byWidgetPredicate(
      (w) => w is CampusTextAction && w.tooltip == 'Account actions',
    );
    await tester.scrollUntilVisible(
      menu,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    // The floating bar overlays the bottom of the extended scroll viewport.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(menu.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CampusTextField), 'Alice renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.accounts.single.label, 'Alice renamed');
    expect(store.accounts.single.cookie, account.cookie);
    expect(store.accounts.single.id, account.id);
    expect(store.accounts.single.groupId, account.groupId);
  });

  testWidgets(
    'widget honors an empty saved selection instead of starting all passes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      ServerSessions.active = enrollmentServer();
      addTearDown(() {
        ServerSessions.active?.close();
        ServerSessions.active = null;
      });
      final alice = SavedAccount(
        id: 'server_$aliceId',
        label: 'Alice',
        cookie: serverSessionReference(aliceId),
      );
      final passes = NfcPassStore();
      await tester.runAsync(() => passes.save(alice, 123));
      await passes.saveSettings(75, alice.id, []);
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(nfcPassChannel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(nfcPassChannel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: NfcPassPage(accounts: [alice], startOnOpen: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Enroll and select passes before using the widget.'),
        findsOneWidget,
      );
      expect(calls, isNot(contains('start')));
      expect(find.text('0 passes selected'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final (locale, startLabel) in [
    ('en', 'Enroll passes'),
    ('ru', 'Подключить пропуска'),
    ('fr', 'Activer les badges'),
    ('pt', 'Registar passes'),
    ('zh', '注册通行证'),
  ]) {
    testWidgets('$locale NFC controls fit a small screen with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(AppThemeMode.dark),
          locale: Locale(locale),
          supportedLocales: const [
            Locale('en'),
            Locale('ru'),
            Locale('fr'),
            Locale('pt'),
            Locale('zh'),
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: NfcPassPage(
              accounts: [
                for (var i = 0; i < 8; i++)
                  SavedAccount(
                    id: '$i',
                    label: 'Account with a long name $i',
                    cookie: 'test-$i',
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(startLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -1300));
      await tester.pumpAndSettle();
      expect(find.text(startLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
