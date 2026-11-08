import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;

import '../l10n/app_text.dart';
import '../services/live_alerts.dart';
import '../services/push_service.dart';

/// Working on/off switch for alerts, shown in the Alerts tab.
/// It saves users/{uid}.notificationsEnabled (the same setting as Profile)
/// and starts or stops live alerts and push notifications straight away.
class NotificationPreferenceCard extends StatefulWidget {
  final bool isDonor;

  const NotificationPreferenceCard({super.key, required this.isDonor});

  @override
  State<NotificationPreferenceCard> createState() =>
      _NotificationPreferenceCardState();
}

class _NotificationPreferenceCardState
    extends State<NotificationPreferenceCard> {
  bool _enabled = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      setState(() => _enabled = doc.data()?['notificationsEnabled'] != false);
    } catch (_) {
      // Keep the default (on) if the setting cannot be read.
    }
  }

  Future<void> _toggle(bool value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _saving) return;

    final previous = _enabled;
    setState(() {
      _enabled = value;
      _saving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'notificationsEnabled': value,
      }, SetOptions(merge: true));

      if (value) {
        LiveAlerts.start(isDonor: widget.isDonor);
        PushService.init();
      } else {
        LiveAlerts.stop();
        PushService.removeToken();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _enabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your preference. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.tune_rounded, color: Color(0xFFE53935)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notification Preferences',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _enabled
                      ? 'Notifications are ON. You will see new requests and updates.'
                      : 'Notifications are OFF. Turn on to get new requests and updates.',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled,
            activeThumbColor: const Color(0xFFE53935),
            onChanged: _saving ? null : _toggle,
          ),
        ],
      ),
    );
  }
}
