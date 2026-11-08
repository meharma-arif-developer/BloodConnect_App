import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n/app_text.dart';

import 'app_messenger.dart';

/// FREE real-time alerts while the app is open (no Cloud Functions needed).
/// Shows a small banner when a new request arrives or a donor responds.
class LiveAlerts {
  LiveAlerts._();

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static bool? _lastIsDonor;
  static int _generation = 0;

  /// Restart with the last role (used when the user turns alerts back on).
  static void resume() {
    final isDonor = _lastIsDonor;
    if (isDonor != null) start(isDonor: isDonor);
  }

  static Future<void> start({required bool isDonor}) async {
    stop();
    _lastIsDonor = isDonor;
    final generation = ++_generation;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Respect the "Notifications" preference.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.data()?['notificationsEnabled'] == false) return;
    } catch (_) {}

    // A newer start/stop happened while we were checking.
    if (generation != _generation) return;

    var firstSnapshot = true;

    final query = FirebaseFirestore.instance
        .collection('donor_requests')
        .where(isDonor ? 'donorId' : 'requesterId', isEqualTo: user.uid);

    _sub = query.snapshots().listen(
      (snapshot) {
        // The first snapshot only contains old data - do not alert for it.
        if (firstSnapshot) {
          firstSnapshot = false;
          return;
        }

        for (final change in snapshot.docChanges) {
          final data = change.doc.data();
          if (data == null) continue;
          final status = (data['status'] ?? '').toString().toLowerCase();

          if (isDonor &&
              change.type == DocumentChangeType.added &&
              status == 'pending') {
            _show('New blood request received. Open Requests to respond.');
          }

          if (!isDonor && change.type == DocumentChangeType.modified) {
            if (status == 'accepted') {
              _show('A donor accepted your request.');
            } else if (status == 'rejected') {
              _show('A donor could not help with your request.');
            } else if (status == 'completed') {
              _show('Your blood request was marked as completed.');
            }
          }
        }
      },
      onError: (Object e) => debugPrint('Live alerts stopped: $e'),
    );
  }

  static void stop() {
    _generation++;
    _sub?.cancel();
    _sub = null;
  }

  static void _show(String message) {
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
