import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart' hide Text;
import '../../l10n/app_strings.dart';
import '../../l10n/app_text.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/geocoder.dart';
import 'blood_camps_screen.dart';

class CommunityMapScreen extends StatefulWidget {
  const CommunityMapScreen({super.key});

  @override
  State<CommunityMapScreen> createState() => _CommunityMapScreenState();
}

class _CommunityMapScreenState extends State<CommunityMapScreen> {
  final MapController _mapController = MapController();

  LatLng? _currentLocation; // where the phone is (GPS)

  // The place whose hospitals / labs / blood banks are shown. It is the GPS
  // position, or any city / area the user searched for.
  LatLng? _center;
  String _centerLabel = 'My location';
  bool _usingSearch = false;
  bool _isSearching = false;
  int _radiusKm = 5;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isLoadingPlaces = false;
  bool _locationPermissionDenied = false;
  bool _locationServiceDisabled = false;

  String _selectedCategory = 'All';

  List<NearbyPlace> _places = [];

  final List<String> _categories = ['All', 'Blood', 'Hospitals', 'Labs'];

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
  }

  // ============================================================
  // GET CURRENT LOCATION
  // ============================================================

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _locationPermissionDenied = false;
      _locationServiceDisabled = false;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
          _locationServiceDisabled = true;
        });

        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
          _locationPermissionDenied = true;
        });

        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final location = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      setState(() {
        _currentLocation = location;
        _center = location;
        _centerLabel = 'My location';
        _usingSearch = false;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _center == null) return;

        _moveMap(_center!);
      });

      await _loadNearbyPlaces();
    } catch (e) {
      debugPrint('Location error: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to get your current location.', isError: true);
    }
  }

  // ============================================================
  // LOAD NEARBY PLACES FROM OPENSTREETMAP
  // ============================================================

  Future<void> _loadNearbyPlaces() async {
    if (_center == null) return;

    if (mounted) {
      setState(() {
        _isLoadingPlaces = true;
      });
    }

    try {
      final lat = _center!.latitude;
      final lon = _center!.longitude;

      final radius = _radiusKm * 1000;

      final query =
          '''
[out:json][timeout:25];

(
  nwr["amenity"="hospital"](around:$radius,$lat,$lon);
  nwr["healthcare"="hospital"](around:$radius,$lat,$lon);

  nwr["healthcare"="blood_bank"](around:$radius,$lat,$lon);
  nwr["healthcare"="blood_donation"](around:$radius,$lat,$lon);

  nwr["healthcare"="laboratory"](around:$radius,$lat,$lon);
  nwr["amenity"="clinic"](around:$radius,$lat,$lon);
);

out center tags;
''';

      final Map<String, dynamic> json = await _fetchOverpass(query);

      final List<dynamic> elements = json['elements'] ?? [];

      final List<NearbyPlace> loadedPlaces = [];

      for (final element in elements) {
        final tags = Map<String, dynamic>.from(element['tags'] ?? {});

        double? placeLat;
        double? placeLon;

        if (element['type'] == 'node') {
          placeLat = (element['lat'] as num?)?.toDouble();
          placeLon = (element['lon'] as num?)?.toDouble();
        } else {
          final center = element['center'];

          if (center != null) {
            placeLat = (center['lat'] as num?)?.toDouble();

            placeLon = (center['lon'] as num?)?.toDouble();
          }
        }

        if (placeLat == null || placeLon == null) {
          continue;
        }

        final category = _detectCategory(tags);

        if (category == null) {
          continue;
        }

        final distance = _calculateDistanceKm(lat, lon, placeLat, placeLon);

        loadedPlaces.add(
          NearbyPlace(
            id: '${element['type']}_${element['id']}',
            name: _getPlaceName(tags, category),
            category: category,
            latitude: placeLat,
            longitude: placeLon,
            distanceKm: distance,
            phone:
                tags['phone']?.toString() ?? tags['contact:phone']?.toString(),
            address: _getAddress(tags),
          ),
        );
      }

      loadedPlaces.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

      final uniquePlaces = <String, NearbyPlace>{};

      for (final place in loadedPlaces) {
        final key =
            '${place.name.toLowerCase()}_${place.category}_${place.latitude.toStringAsFixed(2)}_${place.longitude.toStringAsFixed(2)}';

        if (!uniquePlaces.containsKey(key)) {
          uniquePlaces[key] = place;
        }
      }

      if (!mounted) return;

      setState(() {
        _places = uniquePlaces.values.toList();
        _isLoadingPlaces = false;
      });
    } catch (e) {
      debugPrint('Nearby places error: $e');

      if (!mounted) return;

      setState(() {
        _isLoadingPlaces = false;
      });

      _showMessage(
        'Nearby facilities could not be loaded. Please try again.',
        isError: true,
      );
    }
  }

  // ============================================================
  // OVERPASS (tries a second server if the first one is busy)
  // ============================================================

  static const List<String> _overpassServers = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  Future<Map<String, dynamic>> _fetchOverpass(String query) async {
    Object? lastError;

    for (final server in _overpassServers) {
      try {
        final uri = Uri.parse(server).replace(queryParameters: {'data': query});

        final response = await http
            .get(uri, headers: {'User-Agent': 'BloodConnect/1.0'})
            .timeout(const Duration(seconds: 40));

        if (response.statusCode != 200) {
          throw Exception('Overpass API error: ${response.statusCode}');
        }

        return jsonDecode(utf8.decode(response.bodyBytes))
            as Map<String, dynamic>;
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception('Overpass failed: $lastError');
  }

  // ============================================================
  // SEARCH ANY CITY / AREA
  // ============================================================

  double get _zoomForRadius => _radiusKm <= 5 ? 13.5 : (_radiusKm <= 10 ? 12.5 : 11.5);

  void _moveMap(LatLng point) {
    try {
      _mapController.move(point, _zoomForRadius);
    } catch (_) {
      // The map is not on screen yet; it starts at the new centre anyway.
    }
  }

  Future<void> _searchPlace(String query) async {
    final text = query.trim();
    if (text.isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _isSearching = true);

    final result = await Geocoder.search(text);

    if (!mounted) return;

    if (result == null) {
      setState(() => _isSearching = false);
      _showMessage(
        'Could not find this place. Check the name and the internet.',
        isError: true,
      );
      return;
    }

    final point = LatLng(result.lat, result.lng);

    setState(() {
      _center = point;
      _centerLabel = result.shortName;
      _usingSearch = true;
      _isSearching = false;
      _isLoading = false;
      _places = [];
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _moveMap(point);
    });

    await _loadNearbyPlaces();
  }

  /// Back to the places around the phone's GPS position.
  Future<void> _useMyLocation() async {
    _searchController.clear();

    if (_currentLocation == null) {
      await _getCurrentLocation();
      return;
    }

    if (!_usingSearch) {
      _moveMap(_currentLocation!);
      return;
    }

    setState(() {
      _center = _currentLocation;
      _centerLabel = 'My location';
      _usingSearch = false;
      _places = [];
    });

    _moveMap(_currentLocation!);
    await _loadNearbyPlaces();
  }

  Future<void> _askCityDialog() async {
    final controller = TextEditingController();

    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Search a city or area'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: AppStrings.tr('e.g. Lahore')),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (query != null && query.trim().isNotEmpty) {
      await _searchPlace(query);
    }
  }

  // ============================================================
  // DETECT CATEGORY
  // ============================================================

  String? _detectCategory(Map<String, dynamic> tags) {
    final healthcare = tags['healthcare']?.toString().toLowerCase();

    final amenity = tags['amenity']?.toString().toLowerCase();

    if (healthcare == 'blood_bank' || healthcare == 'blood_donation') {
      return 'Blood';
    }

    if (healthcare == 'laboratory') {
      return 'Labs';
    }

    if (amenity == 'hospital' || healthcare == 'hospital') {
      return 'Hospitals';
    }

    if (amenity == 'clinic') {
      return 'Hospitals';
    }

    return null;
  }

  // ============================================================
  // PLACE NAME
  // ============================================================

  String _getPlaceName(Map<String, dynamic> tags, String category) {
    final name = tags['name']?.toString().trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    switch (category) {
      case 'Blood':
        return 'Blood Bank / Donation Center';

      case 'Hospitals':
        return 'Hospital / Clinic';

      case 'Labs':
        return 'Medical Laboratory';

      default:
        return 'Healthcare Facility';
    }
  }

  // ============================================================
  // ADDRESS
  // ============================================================

  String _getAddress(Map<String, dynamic> tags) {
    final parts = <String>[];

    final houseNumber = tags['addr:housenumber']?.toString();

    final street = tags['addr:street']?.toString();

    final city = tags['addr:city']?.toString();

    if (houseNumber != null && houseNumber.isNotEmpty) {
      parts.add(houseNumber);
    }

    if (street != null && street.isNotEmpty) {
      parts.add(street);
    }

    if (city != null && city.isNotEmpty) {
      parts.add(city);
    }

    if (parts.isEmpty) {
      return 'Address not available';
    }

    return parts.join(', ');
  }

  // ============================================================
  // DISTANCE
  // ============================================================

  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371.0;

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a =
        pow(sin(dLat / 2), 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            pow(sin(dLon / 2), 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  // ============================================================
  // FILTER
  // ============================================================

  List<NearbyPlace> get _filteredPlaces {
    if (_selectedCategory == 'All') {
      return _places;
    }

    return _places
        .where((place) => place.category == _selectedCategory)
        .toList();
  }

  // ============================================================
  // MAP MARKERS
  // ============================================================

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    // Pin for a searched city / area (the red dot below is the phone itself).
    if (_usingSearch && _center != null) {
      markers.add(
        Marker(
          point: _center!,
          width: 46,
          height: 46,
          child: const Icon(
            Icons.place_rounded,
            color: Color(0xFF1E88E5),
            size: 42,
          ),
        ),
      );
    }

    if (_currentLocation != null) {
      markers.add(
        Marker(
          point: _currentLocation!,
          width: 58,
          height: 58,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.person_pin_circle,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      );
    }

    for (final place in _filteredPlaces) {
      markers.add(
        Marker(
          point: LatLng(place.latitude, place.longitude),
          width: 48,
          height: 48,
          child: GestureDetector(
            onTap: () {
              _showPlaceDetails(place);
            },
            child: Container(
              decoration: BoxDecoration(
                color: _categoryColor(place.category),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Icon(
                _categoryIcon(place.category),
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  // ============================================================
  // CATEGORY ICON
  // ============================================================

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'Blood':
        return Icons.bloodtype_rounded;

      case 'Hospitals':
        return Icons.local_hospital_rounded;

      case 'Labs':
        return Icons.science_rounded;

      default:
        return Icons.location_on_rounded;
    }
  }

  // ============================================================
  // CATEGORY COLOR
  // ============================================================

  Color _categoryColor(String category) {
    switch (category) {
      case 'Blood':
        return const Color(0xFFE53935);

      case 'Hospitals':
        return const Color(0xFF1976D2);

      case 'Labs':
        return const Color(0xFF7B1FA2);

      default:
        return Colors.grey;
    }
  }

  // ============================================================
  // PLACE DETAILS
  // ============================================================

  void _showPlaceDetails(NearbyPlace place) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _categoryColor(place.category)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        _categoryIcon(place.category),
                        color: _categoryColor(place.category),
                        size: 28,
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '${place.category} • ${place.distanceKm.toStringAsFixed(1)} km away',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                _PlaceInfoRow(
                  icon: Icons.location_on_outlined,
                  text: place.address,
                ),

                if (place.phone != null && place.phone!.isNotEmpty) ...[
                  const SizedBox(height: 10),

                  _PlaceInfoRow(icon: Icons.phone_outlined, text: place.phone!),
                ],

                const SizedBox(height: 20),

                Row(
                  children: [
                    if (place.phone != null && place.phone!.isNotEmpty)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _callPlace(place.phone!);
                          },
                          icon: const Icon(Icons.call_rounded),
                          label: const Text('Call'),
                        ),
                      ),

                    if (place.phone != null && place.phone!.isNotEmpty)
                      const SizedBox(width: 10),

                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _openDirections(place);
                        },
                        icon: const Icon(Icons.directions_rounded),
                        label: const Text('Directions'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // CALL
  // ============================================================

  Future<void> _callPlace(String phone) async {
    final cleanedPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');

    final uri = Uri(scheme: 'tel', path: cleanedPhone);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showMessage('Unable to open phone dialer.', isError: true);
      }
    } catch (e) {
      debugPrint('Call error: $e');

      _showMessage('Unable to make the call.', isError: true);
    }
  }

  // ============================================================
  // DIRECTIONS
  // ============================================================

  Future<void> _openDirections(NearbyPlace place) async {
    final origin = _currentLocation;

    final destinationLat = place.latitude;

    final destinationLon = place.longitude;

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '${origin == null ? '' : '&origin=${origin.latitude},${origin.longitude}'}'
      '&destination=$destinationLat,$destinationLon'
      '&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showMessage('Unable to open directions.', isError: true);
      }
    } catch (e) {
      debugPrint('Directions error: $e');

      _showMessage('Unable to open directions.', isError: true);
    }
  }

  // ============================================================
  // LOCATION BUTTON
  // ============================================================

  Future<void> _goToCurrentLocation() async {
    await _useMyLocation();
  }

  // ============================================================
  // LOCATION SETTINGS
  // ============================================================

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  // ============================================================
  // REFRESH
  // ============================================================

  Future<void> _refreshAll() async {
    if (_usingSearch) {
      await _loadNearbyPlaces();
    } else {
      await _getCurrentLocation();
    }
  }

  // ============================================================
  // LOCATION PERMISSION CARD
  // ============================================================

  Widget _buildLocationPermissionCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_off_rounded, size: 56, color: Colors.red),

                const SizedBox(height: 16),

                Text(
                  _locationServiceDisabled
                      ? 'Location Services Are Off'
                      : 'Location Permission Needed',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  _locationServiceDisabled
                      ? 'Please turn on location services so BloodConnect can find nearby facilities.'
                      : 'BloodConnect needs your location to show nearby blood facilities, hospitals and laboratories.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.65),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _locationServiceDisabled
                        ? _openLocationSettings
                        : _openAppSettings,
                    icon: Icon(
                      _locationServiceDisabled
                          ? Icons.location_on
                          : Icons.settings,
                    ),
                    label: Text(
                      _locationServiceDisabled
                          ? 'Turn On Location'
                          : 'Open App Settings',
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                TextButton(
                  onPressed: _getCurrentLocation,
                  child: const Text('Try Again'),
                ),

                OutlinedButton.icon(
                  onPressed: _askCityDialog,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Search a city instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // FILTER BAR
  // ============================================================

  Widget _buildFilterBar() {
    return Positioned(
      left: 12,
      right: 12,
      top: 76,
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final category = _categories[index];

            final selected = _selectedCategory == category;

            return ChoiceChip(
              label: Text(category),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedCategory = category;
                });
              },
              selectedColor: const Color(0xFFE53935),
              backgroundColor: Theme.of(context).cardColor,
              labelStyle: TextStyle(
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // RADIUS BAR (how far around the chosen place to look)
  // ============================================================

  Widget _buildRadiusBar() {
    final theme = Theme.of(context);

    return Positioned(
      left: 12,
      right: 12,
      top: 126,
      child: Row(
        children: [
          for (final km in const [5, 10, 20]) ...[
            ChoiceChip(
              label: Text('$km km'),
              selected: _radiusKm == km,
              onSelected: (_) {
                if (_radiusKm == km) return;
                setState(() => _radiusKm = km);
                if (_center != null) {
                  _moveMap(_center!);
                  _loadNearbyPlaces();
                }
              },
              selectedColor: const Color(0xFFE53935),
              backgroundColor: theme.cardColor,
              labelStyle: TextStyle(
                color: _radiusKm == km
                    ? Colors.white
                    : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_filteredPlaces.length} places • $_centerLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PLACES LIST
  // ============================================================

  Widget _buildPlacesList() {
    final places = _filteredPlaces;

    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 230),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: places.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'No nearby facilities found in this category.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(8),
                itemCount: places.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final place = places[index];

                  return ListTile(
                    dense: true,
                    onTap: () {
                      _mapController.move(
                        LatLng(place.latitude, place.longitude),
                        16,
                      );

                      _showPlaceDetails(place);
                    },
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _categoryColor(place.category)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _categoryIcon(place.category),
                        color: _categoryColor(place.category),
                      ),
                    ),
                    title: Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      '${place.distanceKm.toStringAsFixed(1)} km • ${place.category}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                    ),
                  );
                },
              ),
      ),
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nearby Community',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Blood Camps',
            icon: const Icon(Icons.event_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BloodCampsScreen(
                  initialCity: _usingSearch ? _centerLabel : null,
                ),
              ),
            ),
          ),
          if (_isLoadingPlaces || _isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFE53935),
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh',
              onPressed: _refreshAll,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE53935)),
            )
          : _center == null
          ? _buildLocationPermissionCard()
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _center!,
                    initialZoom: 14,
                    minZoom: 3,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.bloodconnect.app',
                    ),

                    MarkerLayer(markers: _buildMarkers()),

                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),

                // ==================================================
                // SEARCH ANY CITY / AREA
                // ==================================================
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Material(
                    elevation: 4,
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(14),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _searchPlace,
                      decoration: InputDecoration(
                        hintText: AppStrings.tr('Search city or area (e.g. Lahore)'),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'My location',
                          icon: Icon(
                            Icons.my_location,
                            color: _usingSearch
                                ? Colors.grey
                                : const Color(0xFFE53935),
                          ),
                          onPressed: _useMyLocation,
                        ),
                      ),
                    ),
                  ),
                ),

                _buildFilterBar(),

                _buildRadiusBar(),

                _buildPlacesList(),

                // ==================================================
                // CURRENT LOCATION BUTTON
                // ==================================================
                Positioned(
                  right: 16,
                  bottom: 255,
                  child: FloatingActionButton(
                    heroTag: 'currentLocationButton',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE53935),
                    elevation: 5,
                    onPressed: _goToCurrentLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
    );
  }
}

// ================================================================
// NEARBY PLACE MODEL
// ================================================================

class NearbyPlace {
  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String? phone;
  final String address;

  const NearbyPlace({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.phone,
    required this.address,
  });
}

// ================================================================
// PLACE INFO ROW
// ================================================================

class _PlaceInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PlaceInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFFE53935)),

        const SizedBox(width: 10),

        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
      ],
    );
  }
}
