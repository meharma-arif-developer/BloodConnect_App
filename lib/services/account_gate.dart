import 'package:cloud_firestore/cloud_firestore.dart';

/// Checks whether an account was suspended by an admin.
/// Works on the free Firebase plan (no Cloud Functions needed).
class AccountGate {
  AccountGate._();

  /// Remembers when the user last opened the app (never blocks the app).
  static Future<void> touchLastActive(String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<bool> isSuspended(
    String uid,
    Map<String, dynamic>? userData,
  ) async {
    if (userData?['isActive'] == false) return true;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('suspended_users')
          .doc(uid)
          .get();
      return doc.exists;
    } catch (_) {
      // If the check itself fails (offline), do not lock the user out.
      return false;
    }
  }
}
