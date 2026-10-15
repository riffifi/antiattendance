import 'dart:async';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/screen_navigation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'widget_test.dart' show MemoryAccountStore, MemoryLogStore;

class _CountBuilds extends StatelessWidget {
  const _CountBuilds(this.onBuild);
  final VoidCallback onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.expand();
  }
}

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
    'content follows a held drag without rebuilding or committing a screen',
    (tester) async {
      var builds = 0;
      var selected = 1;
      var selector = true;
      final content = _CountBuilds(() => builds++);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder: (context, update) => ScreenNavigation(
              selectorVisible: selector,
              selectedIndex: selected,
              onIndex: () => update(() => selector = true),
              onSelected: (index) => update(() {
                selected = index;
                selector = false;
              }),
              child: content,
            ),
          ),
        ),
      );
      expect(builds, 1);
      await tester.tap(find.byKey(const ValueKey('screen-selector-1')));
      await tester.pumpAndSettle();
      expect(builds, 1);
      final drag = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('screen-rail'))),
      );
      await drag.moveBy(const Offset(0, -30));
      await tester.pump();
      await drag.moveBy(const Offset(0, -100));
      await tester.pump();
      final transform = tester.widget<Transform>(
        find.byKey(const ValueKey('navigation-content-motion')),
      );
      expect(transform.transform.storage[13], lessThan(0));
      expect(selected, 1);
      expect(builds, 1);
      await drag.cancel();
      await tester.pumpAndSettle();
      expect(selected, 1);
      await tester.tap(find.text('INDEX'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-1')));
      await tester.pumpAndSettle();
      expect(builds, 1);
      tester.widget<ScreenNavigation>(find.byType(ScreenNavigation)).onIndex();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      tester
          .widget<ScreenNavigation>(find.byType(ScreenNavigation))
          .onSelected(2);
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(
        tester
            .widget<PageView>(find.byKey(const ValueKey('screen-rail')))
            .controller!
            .page,
        2,
      );
      expect(builds, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'returning from Settings refreshes in place and retains the attendance scroll state',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = _DelayedAccounts();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomePage(
            startAtSelector: true,
            store: store,
            logStore: MemoryLogStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
      await tester.pumpAndSettle();
      final scroll = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      final original = tester.state<ScrollableState>(scroll);
      await tester.tap(find.text('INDEX'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('INDEX'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
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
