import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'location_helper.dart';

/// A blood donation camp / event posted by a hospital, a donor, an admin or
/// anyone else. Stored in the Firestore collection `blood_camps`.
class BloodCamp {
  const BloodCamp({
    required this.id,
    required this.title,
    required this.organizer,
    required this.organizerType,
    required this.city,
    required this.address,
    required this.date,
    required this.timeText,
    required this.phone,
    required this.description,
    required this.createdBy,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String title;
  final String organizer;
  final String organizerType;
  final String city;
  final String address;
  final DateTime date;
  final String timeText;
  final String phone;
  final String description;
  final String createdBy;
  final double? latitude;
  final double? longitude;

  bool get isMine => FirebaseAuth.instance.currentUser?.uid == createdBy;

  static String _s(dynamic v) => v == null ? '' : v.toString();

  factory BloodCamp.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final ts = d['date'];
    return BloodCamp(
      id: doc.id,
      title: _s(d['title']),
      organizer: _s(d['organizer']),
      organizerType: _s(d['organizerType']),
      city: _s(d['city']),
      address: _s(d['address']),
      date: ts is Timestamp ? ts.toDate() : DateTime.now(),
      timeText: _s(d['timeText']),
      phone: _s(d['phone']),
      description: _s(d['description']),
      createdBy: _s(d['createdBy']),
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
    );
  }
}

class CampService {
  CampService._();

  static const List<String> organizerTypes = [
    'Hospital',
    'Blood Donor',
    'Organization / NGO',
    'Other',
  ];

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('blood_camps');

  static DateTime get _startOfToday {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// All camps from today onwards, soonest first. Camps of past days
  /// disappear by themselves.
  static Stream<List<BloodCamp>> upcoming() {
    return _col
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfToday))
        .orderBy('date')
        .limit(150)
        .snapshots()
        .map((snap) => snap.docs.map(BloodCamp.fromDoc).toList());
  }

  static Future<void> add({
    required String title,
    required String organizer,
    required String organizerType,
    required String city,
    required String address,
    required DateTime date,
    required String timeText,
    required String phone,
    required String description,
    double? latitude,
    double? longitude,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please log in first.');

    await _col.add({
      'title': title,
      'organizer': organizer,
      'organizerType': organizerType,
      'city': city,
      'address': address,
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'timeText': timeText,
      'phone': phone,
      'description': description,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
  }

  static Future<void> delete(String id) => _col.doc(id).delete();

  /// First part of "City, Area" (how a city may be saved in a profile).
  static String cityOnly(String text) => text.split(',').first.trim();

  /// True when the camp belongs to [city] (text match) or lies within
  /// [radiusKm] of the given position.
  static bool isNear(
    BloodCamp camp, {
    String? city,
    double? lat,
    double? lng,
    double radiusKm = 40,
  }) {
    if (lat != null &&
        lng != null &&
        camp.latitude != null &&
        camp.longitude != null) {
      return LocationHelper.distanceKm(
            lat,
            lng,
            camp.latitude!,
            camp.longitude!,
          ) <=
          radiusKm;
    }
    final wanted = cityOnly(city ?? '').toLowerCase();
    if (wanted.isEmpty) return false;
    final have = cityOnly(camp.city).toLowerCase();
    return have == wanted || have.contains(wanted) || wanted.contains(have);
  }
}
