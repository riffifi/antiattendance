import 'dart:convert';

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/debug_menu_page.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/nfc_pass.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'widget_test.dart' show MemoryAccountStore, MemoryLogStore;

class _BrokenSettings extends AppSettingsStore {
  @override
  Future<bool> loadDaySummaryEnabled() async =>
      throw StateError('secret-error-token');
}

PackageInfo _package() => PackageInfo(
  appName: 'AntiAttendance',
  packageName: 'example.app',
  version: '3.3.9',
  buildNumber: '28',
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'report includes session health but excludes credentials and pass data',
    () async {
      const account = SavedAccount(
        id: 'private-id',
        label: 'Private Name',
        cookie: 'secret-cookie',
        groupId: 42,
        sessionExpired: true,
      );
      final passes = NfcPassStore();
      await passes.saveSettings(75, account.id, [account.id], true, account.id);
      final collector = DebugReportCollector(
        packageInfo: () async => _package(),
        passes: passes,
        nativeSnapshot: () async => {
          'model': 'Test phone',
          'nfc_enabled': true,
          'token': 'native-secret',
          'queue': {
            'armed': false,
            'accountId': 'private-id',
            'number': 12345678,
            'token': 'queue-secret',
          },
        },
      );
      final report = await collector.collect(
        accounts: [account],
        selected: {account.id},
        appState: {'appearance': 'dark'},
        display: {'pixel_ratio': 2},
        settings: AppSettingsStore(),
      );
      final encoded = jsonEncode(report);
      for (final secret in [
        'private-id',
        'Private Name',
        'secret-cookie',
        '12345678',
        'native-secret',
        'queue-secret',
      ]) {
        expect(encoded, isNot(contains(secret)), reason: secret);
      }
      final sessions = report['Accounts & sessions']! as Map;
      expect(sessions['expired'], 1);
      expect(sessions['selected'], 1);
      expect(sessions['enrolled_passes'], 0); // the phone keeps no passes
      final nfc = report['NFC & widgets']! as Map;
      expect((nfc['queue_preferences'] as Map)['mode'], 'single');
      expect((nfc['queue_preferences'] as Map)['delay_seconds'], 75);
      expect((nfc['queue'] as Map)['armed'], false);
    },
  );

  test(
    'missing native support and storage errors preserve the rest of the report',
    () async {
      final collector = DebugReportCollector(
        packageInfo: () async => _package(),
        nativeSnapshot: () async =>
            throw MissingPluginException('secret-error-token'),
      );
      final report = await collector.collect(
        accounts: [],
        selected: {},
        appState: {},
        display: {},
        settings: _BrokenSettings(),
      );
      expect((report['App']! as Map)['version'], '3.3.9');
      expect(
        (report['Device']! as Map)['native_diagnostics'],
        'Not available on this platform',
      );
      expect(
        (report['NFC & widgets']! as Map)['day_summary_enabled'],
        'Could not read diagnostics',
      );
      expect(jsonEncode(report), isNot(contains('secret-error-token')));
    },
  );

  testWidgets(
    'five downward rail swipes reveal session-only developer destination and report can be copied',
    (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'AntiAttendance',
        packageName: 'example.app',
        version: '3.3.9',
        buildNumber: '28',
        buildSignature: '',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('antiattendance/debug'),
        (_) async => {'model': 'Test phone', 'nfc_available': true},
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('antiattendance/debug'),
          null,
        ),
      );
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomePage(
            startAtSelector: true,
            store: MemoryAccountStore([
              const SavedAccount(
                id: 'a',
                label: 'Private Name',
                cookie: 'secret-cookie',
              ),
            ]),
            logStore: MemoryLogStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
      await tester.pumpAndSettle();
      final rail = find.byKey(const ValueKey('screen-rail'));
      for (var swipe = 0; swipe < 4; swipe++) {
        await tester.drag(rail, const Offset(0, 220));
        await tester.pumpAndSettle();
        expect(find.byType(DebugMenuPage), findsNothing);
      }
      await tester.drag(rail, const Offset(0, 220));
      await tester.pumpAndSettle();
      expect(find.byType(DebugMenuPage), findsOneWidget);
      expect(find.text('00'), findsOneWidget);
      expect(find.text('Developer'), findsWidgets);
      expect(find.text('App'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy report'));
      await tester.pumpAndSettle();
      final report = jsonDecode(copied!) as Map;
      expect((report['App'] as Map)['version'], '3.3.9');
      expect((report['Device'] as Map)['model'], 'Test phone');
      expect(copied, isNot(contains('secret-cookie')));
      expect(copied, isNot(contains('Private Name')));
      await tester.drag(rail, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(find.text('01'), findsOneWidget);
      await tester.drag(rail, const Offset(0, 420));
      await tester.pumpAndSettle();
      expect(find.text('00'), findsOneWidget);
      await tester.tap(find.text('INDEX'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('screen-selector-4')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
      await tester.pumpAndSettle();
      await tester.drag(rail, const Offset(0, 420));
      await tester.pumpAndSettle();
      expect(find.text('00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomePage(
            startAtSelector: true,
            store: MemoryAccountStore([]),
            logStore: MemoryLogStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
      await tester.pumpAndSettle();
      expect(find.byType(DebugMenuPage), findsNothing);
      expect(
        tester.widget<PageView>(rail).childrenDelegate.estimatedChildCount,
        4,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'every section can expand, collapse and reopen without storage collisions',
    (tester) async {
      final report = {
        for (final section in [
          'App',
          'Device',
          'Display & accessibility',
          'Performance',
          'Accounts & sessions',
          'Session server',
          'NFC & widgets',
          'Updates',
        ])
          section: {'diagnostic_value': 'content for $section'},
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DebugMenuPage(loadReport: (_) async => report),
        ),
      );
      await tester.pumpAndSettle();
      for (final section in report.keys) {
        final tile = find.byWidgetPredicate(
          (w) =>
              w is ExpansionTile && w.key == PageStorageKey('debug-$section'),
        );
        for (var cycle = 0; cycle < 2; cycle++) {
          await tester.scrollUntilVisible(
            tile,
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(of: tile, matching: find.text(section)),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Opening $section, cycle $cycle',
          );
          expect(find.textContaining('content for $section'), findsOneWidget);
          await tester.tap(
            find.descendant(of: tile, matching: find.text(section)),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Closing $section, cycle $cycle',
          );
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('diagnostics support a narrow screen and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppThemeMode.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: DebugMenuPage(
          loadReport: (_) async {
            calls++;
            return {
              'App': {'version': '3.3.9', 'build': '28'},
              'Device': {
                'model': 'An unusually long device model and manufacturer name',
              },
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.scrollUntilVisible(
      find.text('Session server'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
