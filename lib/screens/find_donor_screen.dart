import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n/app_strings.dart';
import '../l10n/app_text.dart';

import '../config/blood_compatibility.dart';
import '../services/location_helper.dart';
import '../services/push_relay.dart';
import '../services/safety_service.dart';

class FindDonorScreen extends StatefulWidget {
  final String? requestId;

  const FindDonorScreen({super.key, this.requestId});

  @override
  State<FindDonorScreen> createState() => _FindDonorScreenState();
}

class _FindDonorScreenState extends State<FindDonorScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _locationController = TextEditingController();

  final List<String> _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  final List<String> _availabilityOptions = ['Available Only', 'All Donors'];

  String? _selectedBloodGroup;
  String _selectedAvailability = 'Available Only';

  bool _isLoading = true;

  String? _requestBloodGroup;
  String? _requestCity;
  String? _requestCountry;
  double? _myLat;
  double? _myLng;
  bool _isLocating = false;
  String? _requestArea;

  bool _isRequestLoading = false;

  List<Map<String, dynamic>> _allDonors = [];
  List<Map<String, dynamic>> _filteredDonors = [];

  @override
  void initState() {
    super.initState();

    _loadRequestAndDonors();
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOADREQUESTANDDONORS() FROM FIREBASE
  // ============================================================
  Future<void> _loadRequestAndDonors() async {
    if (widget.requestId == null) {
      await _loadDonors();
      return;
    }

    if (!mounted) return;

    setState(() {
      _isRequestLoading = true;
      _isLoading = true;
    });

    try {
      final requestDoc = await _firestore
          .collection('blood_requests')
          .doc(widget.requestId)
          .get();

      if (!requestDoc.exists) {
        throw Exception('Blood request not found.');
      }

      final data = requestDoc.data() ?? {};

      final bloodGroup = (data['bloodGroup'] ?? '').toString();
      final city = (data['city'] ?? '').toString();
      final area = (data['area'] ?? '').toString();

      if (!mounted) return;

      setState(() {
        _requestBloodGroup = bloodGroup;
        _requestCountry = (data['country'] ?? '').toString();
        _requestCity = city;
        _requestArea = area;

        if (_bloodGroups.contains(bloodGroup)) {
          _selectedBloodGroup = bloodGroup;
        }

        if (city.isNotEmpty) {
          _locationController.text = city;
        }

        _isRequestLoading = false;
      });

      await _loadDonors();
    } catch (e) {
      debugPrint('Request loading error: $e');

      if (!mounted) return;

      setState(() {
        _isRequestLoading = false;
        _isLoading = false;
      });

      _showMessage('Unable to load blood request.', isError: true);
    }
  }

  // ============================================================
  // LOAD DONORS FROM FIREBASE
  // ============================================================

  Future<void> _loadDonors() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // When opened from a blood request, ask Firestore for only the
      // matching, available donors instead of downloading everyone.
      Query<Map<String, dynamic>> donorQuery = _firestore.collection(
        'donor_profiles',
      );
      final requestGroup = (_requestBloodGroup ?? '').trim();
      if (widget.requestId != null && requestGroup.isNotEmpty) {
        donorQuery = donorQuery
            .where(
              'bloodGroup',
              whereIn: BloodCompatibility.donorGroupsFor(requestGroup),
            )
            .where('donorAvailable', isEqualTo: true);
      }
      final snapshot = await donorQuery.get();

      // Never show donors this user has blocked.
      final blockedIds = await SafetyService.blockedIds();

      final donors = snapshot.docs
          .where((doc) => !blockedIds.contains(doc.id))
          .map((doc) {
        final data = doc.data();

        return {
          'id': doc.id,
          'userId': data['userId'] ?? doc.id,
          'name': data['name'] ?? 'Unknown Donor',
          'bloodGroup': data['bloodGroup'] ?? 'Not set',
          'city': data['city'] ?? '',
          'country': data['country'] ?? '',
          'area': data['area'] ?? data['location'] ?? '',
          'donorAvailable': data['donorAvailable'] == true,
              'isActive': data['isActive'] != false,
              'latitude': data['latitude'],
              'longitude': data['longitude'],
            };
          })
          .toList();

      if (!mounted) return;

      setState(() {
        _allDonors = donors;
        _filteredDonors = List.from(donors);
        _isLoading = false;
      });

      _applyFilters();
    } on FirebaseException catch (e) {
      debugPrint('Donor loading error: ${e.code} - ${e.message}');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        e.code == 'permission-denied'
            ? 'Firestore permission denied.'
            : 'Unable to load donors.',
        isError: true,
      );
    } catch (e) {
      debugPrint('Donor loading error: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to load donors.', isError: true);
    }
  }

  // ============================================================
  // APPLY FILTERS
  // ============================================================

  void _applyFilters() {
    final location = _locationController.text.trim().toLowerCase();
    final requestBloodGroup = _requestBloodGroup?.trim().toLowerCase();
    final requestCity = _cityKey(_requestCity ?? '');
    final requestCountry = (_requestCountry ?? '').trim().toLowerCase();
    final allowedGroups = BloodCompatibility.donorGroupsFor(
      _requestBloodGroup ?? '',
    ).map((g) => g.trim().toLowerCase()).toSet();

    final filtered = _allDonors.where((donor) {
      final bloodGroup = (donor['bloodGroup'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final city = (donor['city'] ?? '').toString().trim().toLowerCase();
      final country = (donor['country'] ?? '').toString().trim().toLowerCase();
      final area = (donor['area'] ?? '').toString().trim().toLowerCase();
      final available = donor['donorAvailable'] == true;
      final isActive = donor['isActive'] != false;

      // Never show disabled/inactive donor profiles.
      if (!isActive) return false;

      // When opened from a blood request, show donors matching that request.
      if (widget.requestId != null) {
        if (requestBloodGroup != null &&
            requestBloodGroup.isNotEmpty &&
            !allowedGroups.contains(bloodGroup)) {
          return false;
        }

        if (requestCountry.isNotEmpty &&
            country.isNotEmpty &&
            country != requestCountry) {
          return false;
        }

        if (requestCity.isNotEmpty && _cityKey(city) != requestCity) {
          return false;
        }

        if (!available) return false;
      } else {
        if (_selectedBloodGroup != null &&
            bloodGroup != _selectedBloodGroup!.trim().toLowerCase()) {
          return false;
        }

        if (_selectedAvailability == 'Available Only' && !available) {
          return false;
        }

        if (location.isNotEmpty &&
            !city.contains(location) &&
            !area.contains(location) &&
            !country.contains(location)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Donors in the same area as the request come first.
    final requestArea = (_requestArea ?? '').trim().toLowerCase();
    if (widget.requestId != null && requestArea.isNotEmpty) {
      int areaRank(Map<String, dynamic> d) =>
          (d['area'] ?? '').toString().trim().toLowerCase() == requestArea
          ? 0
          : 1;
      filtered.sort((a, b) => areaRank(a).compareTo(areaRank(b)));
    }

    if (!mounted) return;
    setState(() {
      _filteredDonors = filtered;
    });
  }

  // ============================================================
  // SEARCH
  // ============================================================

  void _searchDonors() {
    _applyFilters();

    _showMessage('${_filteredDonors.length} donor(s) found.');
  }

  // ============================================================
  // CLEAR FILTERS
  // ============================================================

  void _clearFilters() {
    setState(() {
      _selectedBloodGroup = null;
      _selectedAvailability = 'Available Only';
      _locationController.clear();
      _filteredDonors = List.from(_allDonors);
    });
  }

  // ============================================================
  // FILTER BOTTOM SHEET
  // ============================================================

  void _openFilters() {
    String? selectedBloodGroup = _selectedBloodGroup;
    String selectedAvailability = _selectedAvailability;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 45,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      const Text(
                        'Filter Donors',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        'Blood Group',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),

                      const SizedBox(height: 10),

                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _bloodGroups.map((group) {
                          final selected = selectedBloodGroup == group;

                          return ChoiceChip(
                            label: Text(group),
                            selected: selected,
                            selectedColor: Colors.red.shade100,
                            onSelected: (value) {
                              setSheetState(() {
                                selectedBloodGroup = value ? group : null;
                              });
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        'Availability',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),

                      const SizedBox(height: 10),

                      Wrap(
                        spacing: 8,
                        children: _availabilityOptions.map((option) {
                          final selected = selectedAvailability == option;

                          return ChoiceChip(
                            label: Text(option),
                            selected: selected,
                            selectedColor: Colors.red.shade100,
                            onSelected: (value) {
                              if (!value) return;

                              setSheetState(() {
                                selectedAvailability = option;
                              });
                            },
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 25),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedBloodGroup = selectedBloodGroup;

                              _selectedAvailability = selectedAvailability;
                            });

                            Navigator.pop(context);

                            _applyFilters();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            'Apply Filters',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // DONOR DETAILS
  // ============================================================

  void _showDonorDetails(Map<String, dynamic> donor) {
    final name = donor['name'].toString();
    final bloodGroup = donor['bloodGroup'].toString();
    final city = donor['city'].toString();
    final country = donor['country'].toString();
    final available = donor['donorAvailable'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),

                const SizedBox(height: 25),

                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.red.shade50,
                  child: const Icon(Icons.person, size: 42, color: Colors.red),
                ),

                const SizedBox(height: 15),

                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 8),

                _buildBloodBadge(bloodGroup),

                const SizedBox(height: 15),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on_outlined, size: 18),
                    const SizedBox(width: 5),
                    Text(_locationDisplay(city, country)),
                  ],
                ),

                const SizedBox(height: 15),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: available
                        ? Colors.green.shade50
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    available ? 'Available to Donate' : 'Currently Unavailable',
                    style: TextStyle(
                      color: available
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                if (available)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);

                        _sendDonorRequest(donor);
                      },
                      icon: const Icon(Icons.bloodtype),
                      label: const Text('Request Donor'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),

                TextButton(
                  onPressed: () async {
                    final sheetContext = context;
                    final blocked = await SafetyActions.showMenu(
                      sheetContext,
                      userId: (donor['userId'] ?? donor['id'] ?? '').toString(),
                      name: (donor['name'] ?? '').toString(),
                    );
                    if (blocked && sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                      _loadDonors();
                    }
                  },
                  child: const Text('Report or block this donor'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // REQUEST DONOR
  // ============================================================

  Future<void> _sendDonorRequest(Map<String, dynamic> donor) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final String? initialRequestId = widget.requestId;
    final donorId = (donor['userId'] ?? donor['id'] ?? '').toString();

    if (currentUser == null) {
      _showMessage('Please log in to request a donor.', isError: true);
      return;
    }

    // Opened from the dashboard (no request attached): let the receiver
    // pick one of their own open requests instead of failing.
    String? chosenRequestId = initialRequestId;
    if (chosenRequestId == null || chosenRequestId.trim().isEmpty) {
      try {
        chosenRequestId = await _chooseOwnPendingRequest(currentUser.uid);
      } on FirebaseException catch (e) {
        debugPrint('Request lookup error: ${e.code} - ${e.message}');
        _showMessage(
          e.code == 'permission-denied'
              ? 'Permission denied. Check your Firestore security rules.'
              : 'Could not load your blood requests. Please try again.',
          isError: true,
        );
        return;
      }
    }
    if (chosenRequestId == null || chosenRequestId.trim().isEmpty) {
      // A message was already shown (or the user closed the chooser).
      return;
    }
    final String requestId = chosenRequestId;

    if (donorId.isEmpty) {
      _showMessage('This donor profile is missing its user ID.', isError: true);
      return;
    }

    if (donorId == currentUser.uid) {
      _showMessage(
        'You cannot send a donor request to your own account.',
        isError: true,
      );
      return;
    }

    try {
      final requestRef = _firestore.collection('blood_requests').doc(requestId);
      final donorRef = _firestore.collection('donor_profiles').doc(donorId);
      final donorRequestRef = _firestore
          .collection('donor_requests')
          .doc('${requestId}_$donorId');

      await _firestore.runTransaction((transaction) async {
        final requestSnapshot = await transaction.get(requestRef);
        final donorSnapshot = await transaction.get(donorRef);
        final existingRequestSnapshot = await transaction.get(donorRequestRef);

        if (!requestSnapshot.exists) {
          throw Exception('Blood request not found.');
        }

        final requestData = requestSnapshot.data() ?? <String, dynamic>{};
        if ((requestData['requesterId'] ?? '').toString() != currentUser.uid) {
          throw Exception(
            'Only the owner of this blood request can contact donors.',
          );
        }

        final requestStatus = (requestData['status'] ?? 'pending')
            .toString()
            .toLowerCase();
        if (requestStatus != 'pending') {
          throw Exception('This blood request is no longer pending.');
        }

        if (!donorSnapshot.exists) {
          throw Exception('This donor profile no longer exists.');
        }

        final donorData = donorSnapshot.data() ?? <String, dynamic>{};
        if (donorData['donorAvailable'] != true ||
            donorData['isActive'] == false) {
          throw Exception('This donor is currently unavailable.');
        }

        final requestBloodGroup = (requestData['bloodGroup'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final donorBloodGroup = (donorData['bloodGroup'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final allowedGroups = BloodCompatibility.donorGroupsFor(
          (requestData['bloodGroup'] ?? '').toString(),
        ).map((g) => g.trim().toLowerCase()).toSet();
        if (requestBloodGroup.isNotEmpty &&
            !allowedGroups.contains(donorBloodGroup)) {
          throw Exception(
            'This donor does not match the requested blood group.',
          );
        }

        final requestCountry = (requestData['country'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final donorCountry = (donorData['country'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (requestCountry.isNotEmpty &&
            donorCountry.isNotEmpty &&
            requestCountry != donorCountry) {
          throw Exception('This donor is not in the requested country.');
        }

        final requestCity = _cityKey((requestData['city'] ?? '').toString());
        final donorCity = _cityKey((donorData['city'] ?? '').toString());
        if (requestCity.isNotEmpty &&
            donorCity.isNotEmpty &&
            requestCity != donorCity) {
          throw Exception('This donor is not in the requested city.');
        }

        if (existingRequestSnapshot.exists) {
          final existingData = existingRequestSnapshot.data() ?? {};
          final existingStatus = (existingData['status'] ?? '')
              .toString()
              .toLowerCase();
          if (existingStatus == 'rejected') {
            throw Exception('This donor has already declined this request.');
          }
          throw Exception('You have already requested this donor.');
        }

        final requesterName = (requestData['requesterName'] ?? '').toString();
        final donorName = (donorData['name'] ?? donor['name'] ?? 'Donor')
            .toString();

        transaction.set(donorRequestRef, {
          'bloodRequestId': requestId,
          'donorId': donorId,
          'requesterId': currentUser.uid,
          'donorName': donorName,
          'donorBloodGroup': (donorData['bloodGroup'] ?? '').toString(),
          'donorCity': (donorData['city'] ?? '').toString(),
          'requesterName': requesterName,
          'bloodGroup': (requestData['bloodGroup'] ?? '').toString(),
          'city': (requestData['city'] ?? '').toString(),
          'hospitalName': (requestData['hospitalName'] ?? '').toString(),
          'unitsRequired': requestData['unitsRequired'] ?? 1,
          'urgency': (requestData['urgency'] ?? 'Normal').toString(),
          'status': 'pending',
          'message': (requestData['description'] ?? '').toString(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      PushRelay.notify('invite', donorRequestRef.id);

      _showMessage('Donor request sent to ${donor['name'] ?? 'donor'}.');
    } on FirebaseException catch (e) {
      debugPrint('Send donor request error: ${e.code} - ${e.message}');
      _showMessage(
        e.code == 'permission-denied'
            ? 'Permission denied. Check your Firestore security rules.'
            : 'Could not send donor request. Please try again.',
        isError: true,
      );
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      _showMessage(message, isError: true);
    }
  }

  // ============================================================
  // SORT BY NEAREST (uses the receiver's approximate location,
  // and only donors who chose to share theirs)
  // ============================================================

  Future<void> _sortByNearest() async {
    setState(() => _isLocating = true);

    final result = await LocationHelper.getApproximate();
    if (!mounted) return;

    if (result.error != null) {
      setState(() => _isLocating = false);
      _showMessage(result.error!, isError: true);
      return;
    }

    final myLat = result.latitude!;
    final myLng = result.longitude!;

    double distanceOf(Map<String, dynamic> donor) {
      final lat = donor['latitude'];
      final lng = donor['longitude'];
      if (lat is! num || lng is! num) return double.infinity;
      return LocationHelper.distanceKm(
        myLat,
        myLng,
        lat.toDouble(),
        lng.toDouble(),
      );
    }

    final sorted = List<Map<String, dynamic>>.from(_filteredDonors)
      ..sort((a, b) => distanceOf(a).compareTo(distanceOf(b)));

    setState(() {
      _myLat = myLat;
      _myLng = myLng;
      _filteredDonors = sorted;
      _isLocating = false;
    });

    if (!sorted.any((d) => distanceOf(d).isFinite)) {
      _showMessage('No donor here has shared a location yet.');
    }
  }

  String _distanceSuffix(Map<String, dynamic> donor) {
    final myLat = _myLat;
    final myLng = _myLng;
    final lat = donor['latitude'];
    final lng = donor['longitude'];
    if (myLat == null || myLng == null || lat is! num || lng is! num) {
      return '';
    }
    final km = LocationHelper.distanceKm(
      myLat,
      myLng,
      lat.toDouble(),
      lng.toDouble(),
    );
    return ' • ~${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  // "Lahore, Johar Town" -> "lahore" (older profiles stored city + area together)
  static String _cityKey(String value) {
    return value.split(',').first.trim().toLowerCase();
  }

  // ============================================================
  // CHOOSE ONE OF THE RECEIVER'S OWN OPEN REQUESTS
  // ============================================================

  Future<String?> _chooseOwnPendingRequest(String uid) async {
    final snapshot = await _firestore
        .collection('blood_requests')
        .where('requesterId', isEqualTo: uid)
        .get();

    final open = snapshot.docs.where((doc) {
      final status = (doc.data()['status'] ?? 'pending')
          .toString()
          .toLowerCase();
      return status == 'pending';
    }).toList();

    if (open.isEmpty) {
      _showMessage(
        'Create a blood request first, then send it to a donor.',
        isError: true,
      );
      return null;
    }

    if (open.length == 1) return open.first.id;

    if (!mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Choose a blood request'),
          children: open.map((doc) {
            final data = doc.data();
            final group = (data['bloodGroup'] ?? '').toString();
            final hospital = (data['hospitalName'] ?? 'Hospital').toString();
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, doc.id),
              child: Text('$group • $hospital'),
            );
          }).toList(),
        );
      },
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _locationDisplay(String city, String country) {
    if (city.isNotEmpty && country.isNotEmpty) {
      return '$city, $country';
    }

    if (city.isNotEmpty) {
      return city;
    }

    if (country.isNotEmpty) {
      return country;
    }

    return 'Location not set';
  }

  Widget _buildBloodBadge(String bloodGroup) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        bloodGroup,
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
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
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        title: const Text(
          'Find a Donor',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Filters',
            onPressed: _openFilters,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),

      body: RefreshIndicator(
        color: Colors.red,
        onRefresh: _loadDonors,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // =================================================
              // INTRO CARD
              // =================================================

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade700, Colors.red.shade400],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.volunteer_activism,
                      color: Colors.white,
                      size: 35,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Find a Blood Donor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Search available donors by blood group and location.',
                      style: TextStyle(color: Colors.white70, height: 1.4),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // =================================================
              // SEARCH CARD
              // =================================================
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Search Donors',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: _locationController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchDonors(),
                      decoration: InputDecoration(
                        hintText: AppStrings.tr('City or area'),
                        prefixIcon: const Icon(Icons.location_on_outlined),
                        suffixIcon: _locationController.text.isNotEmpty
                            ? IconButton(
                                onPressed: () {
                                  setState(() {
                                    _locationController.clear();
                                  });
                                  _applyFilters();
                                },
                                icon: const Icon(Icons.clear),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: _filterChipButton(
                            icon: Icons.bloodtype,
                            text: _selectedBloodGroup ?? 'Blood Group',
                            onTap: _openFilters,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _filterChipButton(
                            icon: Icons.accessibility_new,
                            text: _selectedAvailability,
                            onTap: _openFilters,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _searchDonors,
                            icon: const Icon(Icons.search),
                            label: const Text('Search Donors'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        IconButton(
                          onPressed: _clearFilters,
                          tooltip: 'Clear Filters',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                          ),
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // =================================================
              // RESULTS HEADER
              // =================================================
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Available Donors',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${_filteredDonors.length} found',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isLocating ? null : _sortByNearest,
                  icon: _isLocating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.near_me_outlined, size: 18),
                  label: const Text('Sort by nearest'),
                ),
              ),

              const SizedBox(height: 4),

              // =================================================
              // LOADING
              // =================================================
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 50),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.red),
                  ),
                )
              // =================================================
              // EMPTY STATE
              // =================================================
              else if (_filteredDonors.isEmpty)
                _buildEmptyState()
              // =================================================
              // DONOR LIST
              // =================================================
              else
                ..._filteredDonors.map((donor) => _buildDonorCard(donor)),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // FILTER CHIP BUTTON
  // ============================================================

  Widget _filterChipButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.red),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.red, size: 18),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DONOR CARD
  // ============================================================

  Widget _buildDonorCard(Map<String, dynamic> donor) {
    final name = donor['name'].toString();

    final bloodGroup = donor['bloodGroup'].toString();

    final city = donor['city'].toString();

    final country = donor['country'].toString();

    final available = donor['donorAvailable'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: available ? Colors.green.shade100 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.red.shade50,
                child: const Icon(Icons.person, color: Colors.red, size: 30),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        _buildBloodBadge(bloodGroup),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${_locationDisplay(city, country)}${_distanceSuffix(donor)}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: available ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Text(
                  available ? 'Available to donate' : 'Currently unavailable',
                  style: TextStyle(
                    color: available
                        ? Colors.green.shade700
                        : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              OutlinedButton(
                onPressed: () => _showDonorDetails(donor),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.shade200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('View'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.person_search_rounded,
            size: 55,
            color: Colors.grey.shade400,
          ),

          const SizedBox(height: 15),

          const Text(
            'No donors found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 7),

          Text(
            'Try another blood group, city, or availability filter.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4),
          ),

          const SizedBox(height: 15),

          TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.refresh),
            label: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }
}
