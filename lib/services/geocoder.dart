import 'dart:convert';

import 'package:http/http.dart' as http;

class GeoPlace {
  const GeoPlace({
    required this.lat,
    required this.lng,
    required this.shortName,
    required this.fullName,
  });

  final double lat;
  final double lng;

  /// For example "Lahore".
  final String shortName;

  /// For example "Lahore, Punjab, Pakistan".
  final String fullName;
}

/// Turns a place name (city, area, address) into a map position.
/// Uses the free OpenStreetMap Nominatim service (no key needed).
class Geocoder {
  Geocoder._();

  static Future<GeoPlace?> search(String query) async {
    final text = query.trim();
    if (text.isEmpty) return null;

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': text,
        'format': 'jsonv2',
        'limit': '1',
        'accept-language': 'en',
      });

      final response = await http
          .get(uri, headers: {'User-Agent': 'BloodConnect/1.0'})
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! List || body.isEmpty) return null;

      final item = body.first as Map;
      final lat = double.tryParse('${item['lat']}');
      final lng = double.tryParse('${item['lon']}');
      if (lat == null || lng == null) return null;

      final full = '${item['display_name'] ?? text}';
      var short = '${item['name'] ?? ''}'.trim();
      if (short.isEmpty) short = full.split(',').first.trim();

      return GeoPlace(lat: lat, lng: lng, shortName: short, fullName: full);
    } catch (_) {
      return null;
    }
  }
}
