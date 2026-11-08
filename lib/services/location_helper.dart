import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

class LocationResult {
  final double? latitude;
  final double? longitude;
  final String? error;

  const LocationResult({this.latitude, this.longitude, this.error});
}

/// Approximate location helper. Coordinates are rounded to 2 decimals
/// (about 1 km) so a donor's exact position is never stored.
class LocationHelper {
  LocationHelper._();

  static Future<LocationResult> getApproximate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(
          error: 'Please turn on location (GPS) and try again.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const LocationResult(
          error: 'Location permission was denied.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );

      return LocationResult(
        latitude: _round(position.latitude),
        longitude: _round(position.longitude),
      );
    } catch (_) {
      return const LocationResult(error: 'Could not get your location.');
    }
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;

  /// Straight-line distance in kilometres (haversine).
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    double rad(double d) => d * math.pi / 180;

    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
