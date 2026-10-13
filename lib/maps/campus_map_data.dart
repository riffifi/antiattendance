import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:xml/xml.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'floor_georeference.dart';
import 'indoor_navigation_graph.dart';
import 'indoor_route_planner.dart';

String normalizePlace(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[\s–—-]'), '');

class CampusPlace {
  CampusPlace.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      floorId = json['floor_id'] as String,
      label = json['label'] as String,
      kind = json['kind'] as String,
      x = (json['x'] as num).toDouble(),
      y = (json['y'] as num).toDouble(),
      sourceUrl = json['source_url'] as String?,
      equipment = List<dynamic>.from(json['equipment'] as List? ?? const []),
      menu = List<dynamic>.from(json['menu'] as List? ?? const []);
  final String id, floorId, label, kind;
  final double x, y;
  final String? sourceUrl;
  final List<dynamic> equipment, menu;
}

class CampusFloor {
  CampusFloor.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      label = json['label'] as String,
      level = (json['level'] as num).toInt(),
      svg = json['svg'] as String,
      width = (json['width'] as num).toDouble(),
      height = (json['height'] as num).toDouble(),
      metersPerUnit = (json['meters_per_unit'] as num).toDouble(),
      georeference = FloorGeoreference.fromJson(json);
  final String id, label, svg;
  final int level;
  final double width, height, metersPerUnit;
  final FloorGeoreference georeference;
  late final Map<String, Path> paths = _roomPaths(svg);
  bool contains(FloorPoint point) =>
      point.x >= 0 && point.y >= 0 && point.x <= width && point.y <= height;
}

class CampusMap {
  CampusMap.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      shortTitle = json['short_title'] as String,
      address = json['address'] as String,
      latitude = (json['latitude'] as num).toDouble(),
      longitude = (json['longitude'] as num).toDouble(),
      floors = (json['floors'] as List)
          .map((f) => CampusFloor.fromJson(f as Map<String, dynamic>))
          .toList(),
      places = (json['rooms'] as List)
          .map((r) => CampusPlace.fromJson(r as Map<String, dynamic>))
          .toList();
  final String id, title, shortTitle, address;
  final double latitude, longitude;
  final List<CampusFloor> floors;
  final List<CampusPlace> places;
  CampusFloor floor(String id) => floors.firstWhere((f) => f.id == id);
  List<CampusPlace> search(String query, {String? kind, Set<String>? ids}) {
    final normalized = normalizePlace(query);
    return places
        .where(
          (p) =>
              (kind == null || p.kind == kind) &&
              (ids == null || ids.contains(p.id)) &&
              normalizePlace(p.label).contains(normalized),
        )
        .toList()
      ..sort((a, b) {
        final exactA = normalizePlace(a.label) == normalized;
        final exactB = normalizePlace(b.label) == normalized;
        if (exactA != exactB) return exactA ? -1 : 1;
        return a.label.compareTo(b.label);
      });
  }
}

Map<String, dynamic> _decodeGraph(List<int> bytes) =>
    jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;

class CampusMapRepository {
  static final Map<String, Future<IndoorNavigationGraph>> _graphs = {};
  Future<List<CampusMap>> load() async => Future.wait(
    ['v-78', 'v-86', 's-20'].map(
      (id) async => CampusMap.fromJson(
        jsonDecode(await rootBundle.loadString('assets/maps/campus_$id.json'))
            as Map<String, dynamic>,
      ),
    ),
  );
  Future<IndoorNavigationGraph> graph(String id) => _graphs.putIfAbsent(
    id,
    () async {
      try {
        final bytes = await rootBundle.load('assets/maps/graph_$id.json.gz');
        return IndoorNavigationGraph.fromJson(
          await compute(
            _decodeGraph,
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          ),
        );
      } catch (_) {
        _graphs.remove(id);
        rethrow;
      }
    },
  );
  Future<IndoorRouteResult> route(
    String campus,
    CampusPlace from,
    CampusPlace to, {
    bool avoidStairs = false,
  }) async {
    final data = await graph(campus);
    return IndoorRoutePlanner(data).findRouteBetween(
      startNodeIds: data.nodesForRoom(from.id).map((n) => n.id),
      destinationNodeIds: data.nodesForRoom(to.id).map((n) => n.id),
      options: IndoorRouteOptions(stepFree: avoidStairs),
    );
  }
}

class MapSavedPlacesStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  Future<Set<String>> load() async {
    final value = await _storage.read(key: 'campus_map_favorites');
    if (value == null) return {};
    try {
      return (jsonDecode(value) as List).whereType<String>().toSet();
    } on FormatException {
      return {};
    }
  }

  Future<void> save(Set<String> ids) => _storage.write(
    key: 'campus_map_favorites',
    value: jsonEncode(ids.toList()..sort()),
  );
}

double campusDistance(double latitude, double longitude, CampusMap campus) {
  const radians = math.pi / 180;
  final dy = (latitude - campus.latitude) * 111320;
  final dx =
      (longitude - campus.longitude) * 111320 * math.cos(latitude * radians);
  return math.sqrt(dx * dx + dy * dy);
}

// Pulse room outlines use transformed SVG paths. Keep the actual outlines for
// hit testing rather than treating every room as a circle around its label.
Map<String, Path> _roomPaths(String svg) {
  final document = XmlDocument.parse(svg);
  final result = <String, Path>{};
  for (final element in document.descendants.whereType<XmlElement>().where(
    (e) => e.getAttribute('data-object') != null,
  )) {
    final combined = Path();
    for (final shape in element.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'path',
    )) {
      final data = shape.getAttribute('d');
      if (data == null) continue;
      final matrix = Matrix4.identity();
      final ancestors = <XmlElement>[
        shape,
        ...shape.ancestors.whereType<XmlElement>(),
      ].reversed;
      for (final ancestor in ancestors) {
        matrix.multiply(_svgTransform(ancestor.getAttribute('transform')));
      }
      final path = parseSvgPathData(data)..fillType = PathFillType.evenOdd;
      combined.addPath(path.transform(matrix.storage), Offset.zero);
    }
    if (!combined.getBounds().isEmpty) {
      result[element.getAttribute('data-object')!] = combined;
    }
  }
  return result;
}

Matrix4 _svgTransform(String? text) {
  final result = Matrix4.identity();
  if (text == null) return result;
  for (final match in RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)').allMatches(text)) {
    final values = RegExp(r'[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?')
        .allMatches(match.group(2)!)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    final transform = Matrix4.identity();
    switch (match.group(1)) {
      case 'matrix' when values.length == 6:
        transform
          ..setEntry(0, 0, values[0])
          ..setEntry(1, 0, values[1])
          ..setEntry(0, 1, values[2])
          ..setEntry(1, 1, values[3])
          ..setEntry(0, 3, values[4])
          ..setEntry(1, 3, values[5]);
      case 'translate' when values.isNotEmpty:
        transform
          ..setEntry(0, 3, values[0])
          ..setEntry(1, 3, values.length > 1 ? values[1] : 0);
      case 'scale' when values.isNotEmpty:
        transform
          ..setEntry(0, 0, values[0])
          ..setEntry(1, 1, values.length > 1 ? values[1] : values[0]);
      default:
        throw FormatException('Unsupported floor transform: ${match.group(1)}');
    }
    result.multiply(transform);
  }
  return result;
}
