import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Asks the FREE push relay (Cloudflare Worker, see /push_relay) to send a push.
/// Never throws and never blocks the screen: if the relay is off or down,
/// the in-app Alerts still work.
class PushRelay {
  PushRelay._();

  /// type: 'request' | 'invite' | 'response' | 'message'
  /// For 'message', id is the donor request id and messageId the new message.
  static Future<void> notify(
    String type,
    String id, {
    String? messageId,
  }) async {
    // The Cloud Functions route (pushEnabled) sends pushes by itself.
    if (AppConfig.pushEnabled || AppConfig.pushRelayUrl.isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse('${AppConfig.pushRelayUrl}/notify'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'type': type,
              'id': id,
              if (messageId != null) 'messageId': messageId,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('Push relay replied ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Push relay skipped: $e');
    }
  }
}
