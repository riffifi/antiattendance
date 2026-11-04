import 'frontend_test_helpers.dart';

import 'package:brockmann/brockmann.dart';

import 'dart:async';

import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/editorial_controls.dart';
import 'package:antiattendance/settings_page.dart';
import 'package:antiattendance/study_summary.dart';
import 'package:antiattendance/theme_crossfade.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
    'compact Brockmann switch has a 48 dp gesture target and commits on release',
    (tester) async {
      var value = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: StatefulBuilder(
                builder: (context, update) => CampusSwitch(
                  value: value,
                  onChanged: (next) => update(() => value = next),
                ),
              ),
            ),
          ),
        ),
      );
      final control = find.byType(BrockmannSwitch);
      expect(tester.widget<BrockmannSwitch>(control).compact, isTrue);
      final track = find.descendant(
        of: control,
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 60 && w.height == 48,
        ),
      );
      expect(tester.getSize(track), const Size(60, 48));
      final gesture = await tester.startGesture(tester.getCenter(track));
      await tester.pump(const Duration(milliseconds: 80));
      expect(value, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(value, isTrue);
      expect(tester.widget<BrockmannSwitch>(control).value, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  for (final permission in [true, false]) {
    testWidgets(
      'summary responds immediately and handles permission $permission',
      (tester) async {
        final response = Completer<bool>();
        final enableCalls = <bool>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          studySummaryChannel,
          (call) async {
            if (call.method == 'requestPermission') return response.future;
            if (call.method == 'enable') {
              enableCalls.add((call.arguments as Map)['enabled'] as bool);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            studySummaryChannel,
            null,
          ),
        );
        final store = AppSettingsStore();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.android),
            home: SettingsPage(
              store: store,
              language: 'en',
              onLanguageChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byType(CampusSwitch),
          250,
          scrollable: bodyScroll(),
        );
        await tester.ensureVisible(find.byType(CampusSwitch));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(CampusSwitch));
        await tester.pump();
        expect(
          tester.widget<CampusSwitch>(find.byType(CampusSwitch)).value,
          isTrue,
        );
        expect(
          tester.widget<CampusSwitch>(find.byType(CampusSwitch)).onChanged,
          isNull,
        );
        response.complete(permission);
        await tester.pumpAndSettle();
        expect(
          tester.widget<CampusSwitch>(find.byType(CampusSwitch)).value,
          permission,
        );
        expect(
          tester.widget<CampusSwitch>(find.byType(CampusSwitch)).onChanged,
          isNotNull,
        );
        expect(await store.loadDaySummaryEnabled(), permission);
        expect(enableCalls, permission ? [true] : isEmpty);
        if (permission) {
          await tester.ensureVisible(find.byType(CampusSwitch));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(CampusSwitch));
          await tester.pumpAndSettle();
          expect(await store.loadDaySummaryEnabled(), isFalse);
          expect(enableCalls, [true, false]);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'theme crossfade paints a snapshot without recoloring on every frame',
    (tester) async {
      var mode = AppThemeMode.light;
      var builds = 0;
      late StateSetter change;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, update) {
            change = update;
            return MaterialApp(
              theme: AppTheme.build(mode),
              themeAnimationDuration: Duration.zero,
              builder: (context, child) =>
                  ThemeCrossfade(mode: mode, child: child!),
              home: Builder(
                builder: (context) {
                  builds++;
                  return ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                  );
                },
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      change(() => mode = AppThemeMode.dark);
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      final afterChange = builds;
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(builds, afterChange);
      }
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
