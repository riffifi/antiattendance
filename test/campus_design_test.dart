import 'package:antiattendance/update_service.dart';
import 'package:antiattendance/updates_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:antiattendance/about_page.dart';
import 'package:antiattendance/settings_page.dart';
import 'package:antiattendance/app_settings.dart';
import 'package:antiattendance/schedule_api.dart';
import 'package:flutter/services.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/attendance_log.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/main.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreviewRelease extends GitHubUpdateService {
  @override
  Future<AppRelease?> latest() async => AppRelease(
    tag: 'v1.3.0',
    page: Uri.parse(
      'https://github.com/riffifi/antiattendance/releases/tag/v1.3.0',
    ),
    publishedAt: DateTime.utc(2026, 10, 4),
    notes: '## A smoother campus\n\n- Smoother navigation and scrolling\n- Theme-aware QR scanning\n- Clearer attendance and passes\n\n## Improvements\n\nReceive an alert when a new version is ready. Update directly from the app.',
  );
}

class _Accounts extends AccountStore {
  @override
  Future<List<SavedAccount>> load() async => const [
    SavedAccount(
      id: 'a',
      label: 'Alex Morgan',
      cookie: 'test',
      groupId: 42,
      groupName: 'ИНБО-10-23',
    ),
    SavedAccount(
      id: 'b',
      label: 'Sam Rivera',
      cookie: 'test',
      groupId: 42,
      groupName: 'ИНБО-10-23',
    ),
    SavedAccount(
      id: 'c',
      label: 'Jamie Park',
      cookie: 'test',
      groupId: 42,
      groupName: 'ИНБО-10-23',
    ),
  ];
}

class _Log extends AttendanceLogStore {
  @override
  Future<List<AttendanceMark>> load() async => [];
}

class _Schedule extends ScheduleApi {
  @override
  Future<List<ScheduleLesson>> lessonsForWeek(
    int groupId,
    DateTime weekStart, {
    bool refresh = false,
  }) async {
    final day = DateTime.now().toUtc().add(const Duration(hours: 3));
    return [
      for (final (index, subject) in [
        'Mathematics',
        'Software engineering',
        'Physics',
      ].indexed)
        ScheduleLesson(
          key: '$index',
          groupId: groupId,
          start: DateTime.utc(day.year, day.month, day.day, 9 + index * 2),
          end: DateTime.utc(day.year, day.month, day.day, 10 + index * 2, 30),
          subject: subject,
          type: index == 2 ? 'Laboratory' : 'Lecture',
          location: 'A-${204 + index}',
          teachers: 'A. Ivanov',
        ),
    ];
  }
}

void main() {
  if (Platform.environment.containsKey('CAMPUS_PREVIEW_DIR')) {
    setUpAll(() async {
      await (FontLoader(
        'Geist',
      )..addFont(rootBundle.load('font/Geist[wght].ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
  }
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final mode in AppThemeMode.values) {
    testWidgets('$mode campus screens fit a small phone with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(mode),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: HomePage(
            store: _Accounts(),
            logStore: _Log(),
            scheduleApi: _Schedule(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final bar = find.byType(CampusNavigation);
      for (final label in ['Schedule', 'Passes', 'Attendance']) {
        await tester.tap(find.descendant(of: bar, matching: find.text(label)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();
      final last = find.byKey(const ValueKey('c'));
      expect(
        tester.getBottomLeft(last).dy,
        lessThan(tester.getTopLeft(bar).dy),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'navigation pill slides, follows a drag, and commits on release',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: CampusNavigation(
                selectedIndex: selected,
                labels: const ['Attendance', 'Schedule', 'Passes'],
                onDestinationSelected: (index) =>
                    setState(() => selected = index),
              ),
            ),
          ),
        ),
      );
      final pill = find.byKey(const ValueKey('navigation-pill'));
      await tester.pumpAndSettle();
      final start = tester.getCenter(pill).dx;
      await tester.tap(find.text('Schedule'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final halfway = tester.getCenter(pill).dx;
      await tester.pumpAndSettle();
      final end = tester.getCenter(pill).dx;
      expect(halfway, greaterThan(start));
      expect(halfway, lessThan(end));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Schedule')),
      );
      await gesture.moveBy(const Offset(90, 0));
      await tester.pump();
      expect(tester.getCenter(pill).dx, greaterThan(end));
      expect(selected, 1);
      await gesture.moveTo(tester.getCenter(find.text('Passes')));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (mode, language) in [
    (AppThemeMode.light, 'en'),
    (AppThemeMode.dark, 'fr'),
    (AppThemeMode.amoled, 'ru'),
  ]) {
    testWidgets(
      '$mode settings and about support large text and reachable actions',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = AppSettingsStore();
        Widget app(Widget page) => MaterialApp(
          theme: AppTheme.build(mode),
          locale: Locale(language),
          supportedLocales: const [Locale('en'), Locale('fr'), Locale('ru')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: page,
        );
        await tester.pumpWidget(
          app(
            SettingsPage(
              store: store,
              language: null,
              onLanguageChanged: (_) {},
              themeMode: mode,
              monetAvailable: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final languageItem = find.byWidgetPredicate(
          (widget) =>
              widget is CampusListItem &&
              widget.leading is Icon &&
              (widget.leading as Icon).icon == Icons.language_rounded,
        );
        await tester.scrollUntilVisible(languageItem, 150);
        await tester.pumpAndSettle();
        await tester.ensureVisible(languageItem);
        await tester.pumpAndSettle();
        await tester.tap(languageItem);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Português'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Português'));
        await tester.pumpAndSettle();
        expect(await store.loadLanguage(), 'pt');
        await tester.pumpWidget(app(const AboutPage(version: '1.2.13')));
        await tester.pumpAndSettle();
        expect(find.text('v1.2.13'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final github = tester.getCenter(find.text('GitHub'));
        expect(github.dy, greaterThan(460));
        expect(github.dy, lessThan(568));
      },
    );
  }

  testWidgets(
    'press feedback cancels during scrolling and respects reduced motion',
    (tester) async {
      Widget app(bool reduce) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Scaffold(
            body: CampusButton.filled(
              onPressed: () {},
              child: const Text('Action'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(false));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Action')),
      );
      await tester.pump(const Duration(milliseconds: 90));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1),
      );
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.up();
      await tester.pumpWidget(app(true));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );
      expect(tester.takeException(), isNull);
    },
  );

  // Opt-in previews let the same real UI be inspected without a device.
  if (Platform.environment['CAMPUS_PREVIEW_DIR'] case final String directory) {
    for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
      testWidgets('$mode design preview', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final updates = UpdateController(
          service: _PreviewRelease(),
          packageInfo: () async => PackageInfo(
            appName: 'AntiAttendance',
            packageName: 'antiattendance',
            version: '1.2.13',
            buildNumber: '13',
          ),
        );
        await updates.check();
        addTearDown(updates.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(mode),
              home: HomePage(
                store: _Accounts(),
                logStore: _Log(),
                scheduleApi: _Schedule(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final (index, label) in [
          'Attendance',
          'Schedule',
          'Passes',
          'Settings',
          'About',
          'Updates',
        ].indexed) {
          if (index >= 3) {
            tester
                .state<NavigatorState>(find.byType(Navigator).first)
                .push(
                  MaterialPageRoute<void>(
                    builder: (_) => index == 3
                        ? SettingsPage(
                            store: AppSettingsStore(),
                            language: null,
                            themeMode: mode,
                            monetAvailable: true,
                            onLanguageChanged: (_) {},
                          )
                        : index == 4
                        ? const AboutPage(version: '1.2.13')
                        : UpdatesPage(updates: updates),
                  ),
                );
            await tester.pumpAndSettle();
          } else if (index != 0) {
            await tester.tap(
              find.descendant(
                of: find.byType(CampusNavigation),
                matching: find.text(label),
              ),
            );
            await tester.pumpAndSettle();
          }
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File('$directory/${mode.name}-${label.toLowerCase()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
