import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Push notification token handling (Android + iOS only).
///
/// Tokens are saved privately in `users/{uid}/fcm_tokens/{token}`.
/// Messages themselves are sent by the Cloud Functions in /functions.
/// Every method catches its own errors so push problems can never break the app.
class PushService {
  PushService._();

  static bool _listening = false;
  static String? _lastToken;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Call after login (dashboards do this in initState).
  static Future<void> init() async {
    if (!AppConfig.pushActive || !_supported) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.data()?['notificationsEnabled'] == false) return;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) {
        await _saveToken(user.uid, token);
      }

      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen((newToken) {
          final current = FirebaseAuth.instance.currentUser;
          if (current != null) {
            _saveToken(current.uid, newToken);
          }
        });
      }
    } catch (e) {
      debugPrint('Push init skipped: $e');
    }
  }

  static Future<void> _saveToken(String uid, String token) async {
    try {
      _lastToken = token;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcm_tokens')
          .doc(token)
          .set({
            'platform': defaultTargetPlatform.name,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Push token save failed: $e');
    }
  }

  /// Call BEFORE signing out or deleting the account.
  static Future<void> removeToken() async {
    if (!AppConfig.pushActive || !_supported) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = _lastToken ?? await FirebaseMessaging.instance.getToken();

      if (user != null && token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('fcm_tokens')
            .doc(token)
            .delete();
      }

      await FirebaseMessaging.instance.deleteToken();
      _lastToken = null;
    } catch (e) {
      debugPrint('Push token cleanup skipped: $e');
    }
  }
}
