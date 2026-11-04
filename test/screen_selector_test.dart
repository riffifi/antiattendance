import 'dart:io';
import 'dart:ui' as ui;

import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/accounts.dart';
import 'package:antiattendance/main.dart';
import 'package:antiattendance/screen_navigation.dart';
import 'package:antiattendance/schedule_api.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

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
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('all destinations fit $width at double text size', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: HomePage(
            useAdaptiveNavigation: true,
            store: MemoryAccountStore(const [
              SavedAccount(id: 'a', label: 'Alex Morgan', cookie: 'test'),
            ]),
            logStore: MemoryLogStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Alex Morgan'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Alex Morgan'), findsOneWidget);
      for (var i = 1; i < 4; i++) {
        tester
            .widget<ScreenNavigation>(find.byType(ScreenNavigation))
            .onSelected(i);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Alex Morgan'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Alex Morgan'), findsOneWidget);
    });
  }
  if (Platform.environment['TYPOGRAPHY_PREVIEW_DIR']
      case final String directory) {
    testWidgets('export typography previews', (tester) async {
      for (final (family, asset) in [
        ('Geist', 'font/Geist[wght].ttf'),
        ('GeistMono', 'font/GeistMono[wght].ttf'),
        (
          'packages/brockmann/Geist',
          'packages/brockmann/assets/fonts/Geist.ttf',
        ),
        (
          'packages/brockmann/Geist Mono',
          'packages/brockmann/assets/fonts/GeistMono.ttf',
        ),
      ]) {
        await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
      }
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
                useAdaptiveNavigation: true,
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

        await capture('attendance');
        for (var destination = 1; destination < 4; destination++) {
          tester
              .widget<ScreenNavigation>(find.byType(ScreenNavigation))
              .onSelected(destination);
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
