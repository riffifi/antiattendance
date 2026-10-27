import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/settings_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'widget_test.dart' show MemoryAccountStore, MemoryLogStore;

class _ThemeStore extends AppSettingsStore {
  @override
  Future<void> saveThemeMode(AppThemeMode value) async {}
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'Monochrome preview colours stay stable while the page theme animates',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var mode = AppThemeMode.light;
      final store = _ThemeStore();
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, update) {
            return MaterialApp(
              theme: AppTheme.build(mode),
              themeAnimationDuration: const Duration(milliseconds: 320),
              themeAnimationCurve: Curves.easeInOutCubic,
              home: SettingsPage(
                store: store,
                language: null,
                onLanguageChanged: (_) {},
                themeMode: mode,
                onThemeModeChanged: (value) => update(() => mode = value),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      List<Color> previewColours() => tester
          .widgetList<Container>(
            find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxHeight == 92,
            ),
          )
          .map((w) => (w.decoration! as BoxDecoration).color!)
          .toList();
      final previews = previewColours();
      expect(previews.length, 3);
      final light =
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
          Theme.of(tester.element(find.byType(SettingsPage)))
              .scaffoldBackgroundColor;
      await tester.tap(find.text('Dark'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final during = Theme.of(tester.element(find.byType(SettingsPage)))
          .scaffoldBackgroundColor;
      expect(during, isNot(light));
      expect(
        during,
        isNot(AppTheme.build(AppThemeMode.dark).scaffoldBackgroundColor),
      );
      expect(previewColours(), previews);
      await tester.pumpAndSettle();
      expect(previewColours(), previews);
      expect(
        Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Settings destinations retain readable labels', (tester) async {
    final theme = AppTheme.build(AppThemeMode.dark)
        .copyWith(platform: TargetPlatform.android);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: SettingsPage(
          store: _ThemeStore(),
          language: null,
          onLanguageChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['Study day summary', 'Mark-all widget']) {
      await tester.scrollUntilVisible(find.text(label), 250);
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('accounts and scan remain reachable without navigation overlap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomePage(
          startAtSelector: true,
          store: MemoryAccountStore([
            for (var i = 0; i < 12; i++)
              SavedAccount(id: '$i', label: 'Student $i', cookie: '$i'),
          ]),
          logStore: MemoryLogStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Student 0'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Student 0')).bottom,
      lessThan(tester.getRect(find.text('Scan QR · 12')).top),
    );
    await tester.scrollUntilVisible(
      find.text('Student 11'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('Student 11')).bottom,
      lessThan(tester.getRect(find.text('Scan QR · 12')).top),
    );
    expect(find.text('Scan QR · 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
