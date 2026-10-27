import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:antiattendance/campus_maps_page.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/maps/campus_map_data.dart';
import 'package:antiattendance/maps/campus_map_canvas.dart';
import 'package:antiattendance/maps/campus_location.dart';

class MemoryPlaces extends MapSavedPlacesStore {
  Set<String> ids = {};
  @override
  Future<Set<String>> load() async => Set.of(ids);
  @override
  Future<void> save(Set<String> value) async {
    ids = Set.of(value);
  }
}

class ReadyMaps extends CampusMapRepository {
  ReadyMaps(this.campuses);
  final List<CampusMap> campuses;
  @override
  Future<List<CampusMap>> load() async => campuses;
}

class TestLocation extends CampusLocationService {
  TestLocation({this.position, this.reason});
  final CampusPosition? position;
  final String? reason;
  final changes = StreamController<CampusPosition>.broadcast();
  @override
  Future<CampusPosition> locate() async {
    if (reason != null) throw CampusLocationException(reason!);
    return position!;
  }

  @override
  Stream<CampusPosition> watch() => changes.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<CampusMap> campuses;
  setUpAll(() async {
    campuses = await CampusMapRepository().load();
    await CampusMapRepository().graph(campuses.first.id);
  });
  Future<void> showMap(
    WidgetTester tester, {
    MemoryPlaces? saved,
    TestLocation? location,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: CampusMapsPage(
          repository: ReadyMaps(campuses),
          savedPlaces: saved ?? MemoryPlaces(),
          location: location,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectRoom(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(CampusTextField).first, name);
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  test('every floor has shapes and searchable tagged room metadata', () {
    for (final campus in campuses) {
      expect(campus.floors, isNotEmpty);
      expect(campus.places.where((p) => p.kind == 'toilet'), isNotEmpty);
      for (final floor in campus.floors) {
        expect(floor.width, greaterThan(0));
        final places = campus.places.where((p) => p.floorId == floor.id);
        for (final place in places) {
          expect(floor.paths.containsKey(place.id), isTrue, reason: place.id);
        }
      }
    }
    expect(campuses.first.search('г1031').first.label, 'Г-103-1');
  });
  testWidgets('room search opens highlighted geometry and saves a favorite', (
    tester,
  ) async {
    final saved = MemoryPlaces();
    await showMap(tester, saved: saved);
    expect(find.text('В-78'), findsOneWidget);
    await selectRoom(tester, 'Г-103-1');
    expect(find.text('Г-103-1 · Floor 0'), findsOneWidget);
    final canvas = tester.widget<CampusMapCanvas>(find.byType(CampusMapCanvas));
    expect(canvas.selected!.label, 'Г-103-1');
    expect(canvas.floor.paths[canvas.selected!.id], isNotNull);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CampusTextAction && w.tooltip == 'Save place',
      ),
    );
    await tester.pumpAndSettle();
    expect(saved.ids, contains(canvas.selected!.id));
    expect(tester.takeException(), isNull);
  });
  testWidgets('tags filter map pins and offer a matching place list', (
    tester,
  ) async {
    await showMap(tester);
    await tester.tap(find.text('Toilets'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CampusMapCanvas>(find.byType(CampusMapCanvas)).kind,
      'toilet',
    );
    final list = find.textContaining('Place list');
    expect(list, findsOneWidget);
    await tester.tap(list);
    await tester.pumpAndSettle();
    expect(find.textContaining('В-78 · Floor 0 · Toilets'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('permission denied leaves manual route start available', (
    tester,
  ) async {
    final location = TestLocation(reason: 'denied');
    addTearDown(location.changes.close);
    await showMap(tester, location: location);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CampusTextAction && w.tooltip == 'My location',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Allow location access or choose a starting place manually.'),
      findsOneWidget,
    );
    await selectRoom(tester, 'Г-103-1');
    await tester.tap(find.text('Start here'));
    await tester.pumpAndSettle();
    expect(find.text('From: Г-103-1 · Floor 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('location needs a manual floor and stops tracking offscreen', (
    tester,
  ) async {
    final floor = campuses.first.floors.first;
    final geo = floor.georeference.pixelToGeographic(950, 360);
    final location = TestLocation(
      position: CampusPosition(
        latitude: geo.latitude,
        longitude: geo.longitude,
        accuracy: 30,
        at: DateTime.now(),
      ),
    );
    addTearDown(location.changes.close);
    await showMap(tester, location: location);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CampusTextAction && w.tooltip == 'My location',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('GPS cannot identify your floor. Select it manually.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Floor 0').last);
    await tester.pumpAndSettle();
    final map = tester.widget<CampusMapCanvas>(find.byType(CampusMapCanvas));
    expect(map.position!.x, closeTo(950, .01));
    expect(map.position!.y, closeTo(360, .01));
    expect(map.accuracyMeters, greaterThan(30));
    expect(location.changes.hasListener, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(location.changes.hasListener, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(location.changes.hasListener, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(location.changes.hasListener, isFalse);
  });
  testWidgets(
    'navigation draws cross-floor routes and shows floor instructions',
    (tester) async {
      await showMap(tester);
      await selectRoom(tester, 'Е-206.1');
      await tester.tap(find.text('Start here'));
      await tester.pumpAndSettle();
      await selectRoom(tester, 'Е-107');
      await tester.runAsync(() async {
        await tester.tap(find.text('Directions'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      final canvas = tester.widget<CampusMapCanvas>(
        find.byType(CampusMapCanvas),
      );
      expect(canvas.route, isNotNull);
      expect(canvas.route!.floorIds.length, greaterThan(1));
      expect(canvas.floor.id, 'v-78-floor2');
      await tester.ensureVisible(find.textContaining('Route steps'));
      await tester.tap(find.textContaining('Route steps'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Take the stairs'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('Take the stairs'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('small phone and large text keep place actions reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(AppThemeMode.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(1.6),
          ),
          child: CampusMapsPage(
            repository: ReadyMaps(campuses),
            savedPlaces: MemoryPlaces(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await selectRoom(tester, 'Г-103-1');
    await tester.ensureVisible(find.text('Directions'));
    expect(tester.takeException(), isNull);
  });
}
