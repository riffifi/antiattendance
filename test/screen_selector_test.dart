import 'dart:io';
import 'dart:ui' as ui;

import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/screen_selector.dart';
import 'package:antiattendance/schedule_api.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'widget_test.dart' show MemoryAccountStore, MemoryLogStore;

class _PreviewSchedule extends ScheduleApi {
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
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets(
      'four full-height columns fit $size with large translated text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final language in ['en', 'ru', 'fr', 'pt', 'zh']) {
          int? chosen;
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              locale: Locale(language),
              supportedLocales: const [
                Locale('en'),
                Locale('ru'),
                Locale('fr'),
                Locale('pt'),
                Locale('zh'),
              ],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: const TextScaler.linear(2),
                ),
                child: Scaffold(
                  body: ScreenSelector(onSelected: (index) => chosen = index),
                ),
              ),
            ),
          );
          for (var index = 0; index < 4; index++) {
            final column = find.byKey(ValueKey('screen-selector-$index'));
            final rect = tester.getRect(column);
            expect(rect.width, closeTo(size.width / 4, .01));
            expect(rect.height, size.height);
            expect(rect.left, closeTo(index * size.width / 4, .01));
            await tester.tap(column);
            expect(chosen, index);
          }
          expect(
            tester
                .widgetList<RotatedBox>(find.byType(RotatedBox))
                .every((box) => box.quarterTurns == 3),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'destinations open from the index and system back returns to it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      expect(find.byType(ScreenSelector), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenSelector), findsNothing);
      expect(find.text('INDEX'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ScreenSelector), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('screen-selector-1')));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenSelector), findsNothing);
      await tester.tap(find.text('INDEX'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('screen-selector-3')));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ScreenSelector), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('all destinations fit a narrow inset phone with enlarged text', (
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
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 34),
            textScaler: const TextScaler.linear(1.5),
          ),
          child: child!,
        ),
        home: HomePage(
          startAtSelector: true,
          store: MemoryAccountStore(const [
            SavedAccount(
              id: 'a',
              label: 'Alex Morgan',
              cookie: 'test',
              groupId: 42,
              groupName: 'CS-42',
            ),
          ]),
          logStore: MemoryLogStore(),
          scheduleApi: _PreviewSchedule(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var index = 0; index < 4; index++) {
      await tester.tap(find.byKey(ValueKey('screen-selector-$index')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Destination $index');
      expect(
        find.byType(Icon),
        findsNothing,
        reason: 'Type-only destination $index',
      );
      if (index == 0) {
        expect(
          tester.getRect(find.text('Scan QR · 1')).bottom,
          lessThanOrEqualTo(606),
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selector exposes four named, actionable semantic buttons', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ScreenSelector(onSelected: (_) {})),
      ),
    );
    for (final label in ['Attendance', 'Schedule', 'Passes', 'Settings']) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        matchesSemantics(
          label: label,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
    }
    semantics.dispose();
  });

  if (Platform.environment['TYPOGRAPHY_PREVIEW_DIR']
      case final String directory) {
    testWidgets('export typography previews', (tester) async {
      await (FontLoader(
        'Geist',
      )..addFont(rootBundle.load('font/Geist[wght].ttf'))).load();
      await (FontLoader(
        'GeistMono',
      )..addFont(rootBundle.load('font/GeistMono[wght].ttf'))).load();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final mode in [AppThemeMode.light, AppThemeMode.dark]) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.build(mode),
              home: HomePage(
                startAtSelector: true,
                themeMode: mode,
                store: MemoryAccountStore(const [
                  SavedAccount(
                    id: 'a',
                    label: 'Alex Morgan',
                    cookie: 'preview',
                    groupId: 42,
                    groupName: 'CS-42',
                  ),
                  SavedAccount(id: 'b', label: 'Sam Rivera', cookie: 'preview'),
                  SavedAccount(id: 'c', label: 'Jamie Park', cookie: 'preview'),
                ]),
                logStore: MemoryLogStore(),
                scheduleApi: _PreviewSchedule(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> capture(String name) async {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(directory).create(recursive: true);
            await File('$directory/$name-${mode.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('selector');
        await tester.tap(find.byKey(const ValueKey('screen-selector-0')));
        await tester.pumpAndSettle();
        await capture('attendance');
        for (var destination = 1; destination < 4; destination++) {
          await tester.tap(find.text('INDEX'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('screen-selector-$destination')),
          );
          await tester.pumpAndSettle();
          await capture(
            ['attendance', 'schedule', 'passes', 'settings'][destination],
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}
