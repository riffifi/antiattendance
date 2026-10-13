import 'dart:async';

import 'package:geolocator/geolocator.dart';

class CampusPosition {
  const CampusPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.at,
  });
  factory CampusPosition.fromPosition(Position p) => CampusPosition(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracy: p.accuracy,
    at: p.timestamp,
  );
  final double latitude, longitude, accuracy;
  final DateTime at;
  bool get usable =>
      latitude.isFinite &&
      longitude.isFinite &&
      accuracy.isFinite &&
      accuracy >= 0 &&
      DateTime.now().difference(at).abs() < const Duration(minutes: 2);
}

class CampusLocationException implements Exception {
  const CampusLocationException(this.reason);
  final String reason;
}

class CampusLocationService {
  static const settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
    timeLimit: Duration(seconds: 25),
  );
  Future<CampusPosition> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CampusLocationException('disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const CampusLocationException('permanent');
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const CampusLocationException('denied');
    }
    try {
      return CampusPosition.fromPosition(
        await Geolocator.getCurrentPosition(locationSettings: settings),
      );
    } on TimeoutException {
      throw const CampusLocationException('timeout');
    }
  }

  Stream<CampusPosition> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    ),
  ).map(CampusPosition.fromPosition);
  Future<bool> openSettings({bool app = false}) =>
      app ? Geolocator.openAppSettings() : Geolocator.openLocationSettings();
}
