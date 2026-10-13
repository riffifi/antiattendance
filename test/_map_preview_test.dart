import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:antiattendance/app_theme.dart';
import 'package:antiattendance/campus_design.dart';
import 'package:antiattendance/campus_maps_page.dart';
import 'package:antiattendance/maps/campus_map_data.dart';
import 'campus_maps_test.dart' show ReadyMaps, MemoryPlaces;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<CampusMap> campuses;
  setUpAll(() async {
    campuses = await CampusMapRepository().load();
    await CampusMapRepository().graph(campuses.first.id);
    await (FontLoader('Geist')..addFont(rootBundle.load('font/Geist[wght].ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('preview campus navigation', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: RepaintBoundary(key: key,
      child: CampusMapsPage(repository: ReadyMaps(campuses), savedPlaces: MemoryPlaces()))));
    await tester.pumpAndSettle();
    Future<void> select(String label) async {
      await tester.enterText(find.byType(CampusTextField).first, label);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
    await select('Е-206.1');
    await tester.tap(find.text('Start here'));
    await tester.pumpAndSettle();
    await select('Е-107');
    await tester.runAsync(() async {
      await tester.tap(find.text('Directions'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/campus-map-preview.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
