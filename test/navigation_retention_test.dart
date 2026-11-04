import 'package:antiattendance/screen_navigation.dart';

import 'dart:async';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'widget_test.dart' show MemoryAccountStore, MemoryLogStore;

class _DelayedAccounts extends MemoryAccountStore {
  _DelayedAccounts()
    : super(const [SavedAccount(id: 'a', label: 'Alice', cookie: 'test')]);
  final refresh = Completer<List<SavedAccount>>();
  var loads = 0;
  @override
  Future<List<SavedAccount>> load() =>
      ++loads == 1 ? super.load() : refresh.future;
}

void main() {
  testWidgets(
    'returning from Settings refreshes in place and retains the attendance scroll state',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = _DelayedAccounts();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomePage(
            useAdaptiveNavigation: true,
            store: store,
            logStore: MemoryLogStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      final scroll = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Alice'),
        250,
        scrollable: scroll,
      );
      final original = tester.state<ScrollableState>(scroll);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      tester
          .widget<ScreenNavigation>(find.byType(ScreenNavigation))
          .onSelected(3);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      expect(store.loads, 2);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.byType(CampusProgress), findsNothing);
      expect(tester.state<ScrollableState>(scroll), same(original));
      store.refresh.complete(store.accounts);
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(scroll), same(original));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
