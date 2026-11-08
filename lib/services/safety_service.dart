import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n/app_text.dart';

/// Report / block helpers.
///
/// Reports go to `reports/{id}` (only admins can read them).
/// Blocks are stored privately in `users/{myUid}/blocked/{otherUid}`.
class SafetyService {
  SafetyService._();

  static const List<String> reportReasons = [
    'Spam or fake profile',
    'Harassment or abuse',
    'Wrong or misleading information',
    'Asking for money',
    'Other',
  ];

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<void> reportUser({
    required String reportedUserId,
    required String reason,
    String description = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please log in first.');
    if (reportedUserId.isEmpty || reportedUserId == user.uid) {
      throw Exception('You cannot report this account.');
    }

    await _db.collection('reports').add({
      'reporterId': user.uid,
      'reportedUserId': reportedUserId,
      'reason': reason,
      'description': description,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> blockUser({
    required String blockedUserId,
    String name = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please log in first.');
    if (blockedUserId.isEmpty || blockedUserId == user.uid) {
      throw Exception('You cannot block this account.');
    }

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('blocked')
        .doc(blockedUserId)
        .set({'name': name, 'createdAt': FieldValue.serverTimestamp()});
  }

  static Future<void> unblockUser(String blockedUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Please log in first.');

    await _db
        .collection('users')
        .doc(user.uid)
        .collection('blocked')
        .doc(blockedUserId)
        .delete();
  }

  static Future<Set<String>> blockedIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return <String>{};

    final snapshot = await _db
        .collection('users')
        .doc(user.uid)
        .collection('blocked')
        .get();

    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> blockedStream() {
    final user = FirebaseAuth.instance.currentUser;
    return _db
        .collection('users')
        .doc(user?.uid ?? '_none_')
        .collection('blocked')
        .snapshots();
  }
}

/// Small dialogs using the app's default Material dialog style.
class SafetyActions {
  SafetyActions._();

  /// Shows "Report / Block". Returns true if the user was blocked.
  static Future<bool> showMenu(
    BuildContext context, {
    required String userId,
    required String name,
  }) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Report or block'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'report'),
              child: const Text('Report this user'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'block'),
              child: const Text('Block this user'),
            ),
          ],
        );
      },
    );

    if (choice == null || !context.mounted) return false;

    if (choice == 'report') {
      await _report(context, userId);
      return false;
    }

    return _block(context, userId, name);
  }

  static Future<void> _report(BuildContext context, String userId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: const Text('Why are you reporting this user?'),
          children: SafetyService.reportReasons
              .map(
                (r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, r),
                  child: Text(r),
                ),
              )
              .toList(),
        );
      },
    );

    if (reason == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await SafetyService.reportUser(reportedUserId: userId, reason: reason);
      messenger.showSnackBar(
        const SnackBar(content: Text('Report sent. Thank you for helping.')),
      );
    } on FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'permission-denied'
                ? 'Permission denied. Please try again later.'
                : 'Could not send the report. Please try again.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  static Future<bool> _block(
    BuildContext context,
    String userId,
    String name,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Block this user?'),
          content: const Text(
            'You will no longer see each other in searches or requests. '
            'You can unblock them later from your profile.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Block'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !context.mounted) return false;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await SafetyService.blockUser(blockedUserId: userId, name: name);
      messenger.showSnackBar(const SnackBar(content: Text('User blocked.')));
      return true;
    } on FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'permission-denied'
                ? 'Permission denied. Please try again later.'
                : 'Could not block this user. Please try again.',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
    return false;
  }
}
