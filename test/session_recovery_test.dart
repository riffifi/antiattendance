import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/session_check.dart';
import 'package:antiattendance/session_recovery_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const accounts = [
    SavedAccount(id: 'healthy', label: 'Healthy', cookie: 'healthy'),
    SavedAccount(
      id: 'alice',
      label: 'Alice',
      cookie: 'alice',
      groupId: 42,
      groupName: 'Group 42',
    ),
    SavedAccount(id: 'bob', label: 'Bob', cookie: 'bob'),
    SavedAccount(id: 'offline', label: 'Offline', cookie: 'offline'),
  ];
  Future<SessionCheckResult> check(SavedAccount account) async =>
      SessionCheckResult(
        account.cookie == 'healthy' || account.cookie.startsWith('new-')
            ? SessionCheckState.valid
            : account.cookie == 'offline'
            ? SessionCheckState.unavailable
            : SessionCheckState.expired,
      );
  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'bulk recovery skips healthy and unknown accounts, saves each login, and resumes skips',
    (tester) async {
      final logins = <String>[];
      final saved = <SavedAccount>[];
      var skipAlice = true;
      await show(
        tester,
        SessionRecoveryPage(
          accounts: accounts,
          checker: check,
          login: (_, account) async {
            logins.add(account.id);
            if (account.id == 'alice' && skipAlice) return null;
            return SavedAccount(
              id: '',
              label: 'Temporary',
              cookie: 'new-${account.id}',
            );
          },
          onSave: (_, next) async {
            saved.add(next);
          },
        ),
      );
      expect(find.text('Ready: 1 · Need sign-in: 2'), findsOneWidget);
      await tester.tap(find.text('Restore sign-ins: 2'));
      await tester.pumpAndSettle();
      expect(logins, ['alice']);
      expect(saved, isEmpty);
      expect(find.textContaining('Skipped — resume later'), findsOneWidget);
      skipAlice = false;
      await tester.tap(find.text('Restore sign-ins: 2'));
      await tester.pumpAndSettle();
      expect(logins, ['alice', 'bob', 'alice']);
      expect(saved.first.id, 'bob');
      expect(saved.last.id, 'alice');
      expect(saved.last.label, 'Alice');
      expect(saved.last.groupId, 42);
      expect(saved.last.groupName, 'Group 42');
      expect(find.text('Ready: 3 · Need sign-in: 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed new login validation never overwrites the saved account',
    (tester) async {
      var saves = 0;
      await show(
        tester,
        SessionRecoveryPage(
          accounts: [accounts[1]],
          checker: check,
          login: (_, account) async =>
              const SavedAccount(id: '', label: '', cookie: 'offline'),
          onSave: (_, next) async {
            saves++;
          },
        ),
      );
      await tester.tap(find.text('Restore sign-ins: 1'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(
        find.text(
          'Could not confirm the new sign-in. Your saved account is kept; try again later.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ready: 0 · Need sign-in: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('recovery remains usable on a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: SessionRecoveryPage(
          accounts: accounts,
          checker: check,
          login: (_, account) async => null,
          onSave: (_, next) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Restore sign-ins: 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
