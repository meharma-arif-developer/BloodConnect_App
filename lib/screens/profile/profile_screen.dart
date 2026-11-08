import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import '../../config/app_config.dart';
import '../../l10n/app_text.dart';
import '../../l10n/language_picker.dart';
import '../../l10n/language_controller.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/live_alerts.dart';
import '../../services/push_service.dart';
import '../blocked_users_screen.dart';
import '../edit_profile_screen.dart';
import '../legal_texts.dart';
import '../../theme_controller.dart';
import '../login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final ThemeController themeController;

  const ProfileScreen({super.key, required this.themeController});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  bool _isUploadingImage = false;

  String _name = 'User';
  String _email = '';
  String _phone = '';
  String _country = '';
  String _city = '';
  String _bloodGroup = 'Not set';
  String _userType = 'donor';

  bool _donorAvailable = false;

  // Base64 profile image
  String _profileImageBase64 = '';

  bool _notificationsEnabled = true;

  // Default is Light
  String _appearance = 'Light';

  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ============================================================
  // LOAD PROFILE
  // ============================================================

  Future<void> _loadProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        if (mounted) {
          setState(() {
            _name = _stringValue(data['name'], 'User');

            _email = _stringValue(data['email'], user.email ?? '');

            _phone = _stringValue(data['phone'], '');

            _country = _stringValue(data['country'], '');

            _city = _stringValue(data['city'], '');

            _bloodGroup = _stringValue(data['bloodGroup'], 'Not set');

            _userType = _stringValue(
              data['userType'] ?? data['role'],
              'donor',
            ).toLowerCase();

            _donorAvailable = data['donorAvailable'] == true;

            // Base64 image
            _profileImageBase64 = _stringValue(data['profileImageBase64'], '');

            _notificationsEnabled = data['notificationsEnabled'] != false;

            _appearance = _stringValue(data['appearance'], 'Light');
            // Light is the default; "System Default" only if chosen on purpose.
            if (_appearance == 'System Default' &&
                data['appearanceChosen'] != true) {
              _appearance = 'Light';
            }

            _language = _stringValue(data['language'], 'English');
            if (LanguageController.byName(_language) == null) {
              _language = 'English';
            }
            LanguageController.instance.setByName(_language);

            _isLoading = false;
          });

          // Apply saved theme
          widget.themeController.setTheme(_appearance);
        }
      } else {
        if (mounted) {
          setState(() {
            _email = user.email ?? '';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Profile loading error: $e');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        _showMessage('Unable to load profile.', isError: true);
      }
    }
  }

  String _stringValue(dynamic value, String fallback) {
    if (value == null) return fallback;

    final text = value.toString().trim();

    if (text.isEmpty) return fallback;

    return text;
  }

  // ============================================================
  // EDIT PROFILE
  // ============================================================

  Future<void> _openEditProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );

    await _loadProfile();
  }

  // ============================================================
  // PROFILE PICTURE - BASE64 + FIRESTORE
  // ============================================================

  Future<void> _changeProfilePicture() async {
    if (_isUploadingImage) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,

        // Compress image
        imageQuality: 55,

        // Keep image small for Firestore
        maxWidth: 500,
        maxHeight: 500,
      );

      if (image == null) return;

      final user = _auth.currentUser;

      if (user == null) {
        _showMessage('Please login again.', isError: true);
        return;
      }

      if (mounted) {
        setState(() {
          _isUploadingImage = true;
        });
      }

      // ----------------------------------------------------------
      // READ IMAGE
      // ----------------------------------------------------------

      final bytes = await image.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('Selected image is empty.');
      }

      // ----------------------------------------------------------
      // CONVERT IMAGE TO BASE64
      // ----------------------------------------------------------

      final base64Image = base64Encode(bytes);

      debugPrint('Image Base64 length: ${base64Image.length}');

      // ----------------------------------------------------------
      // SAVE BASE64 TO FIRESTORE
      // ----------------------------------------------------------

      await _firestore.collection('users').doc(user.uid).set({
        'profileImageBase64': base64Image,
      }, SetOptions(merge: true));

      // ----------------------------------------------------------
      // UPDATE UI
      // ----------------------------------------------------------

      if (!mounted) return;

      setState(() {
        _profileImageBase64 = base64Image;
        _isUploadingImage = false;
      });

      _showMessage('Profile picture updated successfully.');
    } on FirebaseException catch (e) {
      debugPrint(
        'Firebase profile image error: '
        '${e.code} - ${e.message}',
      );

      if (!mounted) return;

      setState(() {
        _isUploadingImage = false;
      });

      String message = 'Profile picture upload failed.';

      if (e.code == 'permission-denied') {
        message = 'Firestore permission denied.';
      } else if (e.code == 'resource-exhausted') {
        message = 'Image is too large for Firestore.';
      } else if (e.code == 'unavailable') {
        message = 'Firebase is temporarily unavailable.';
      }

      _showMessage(message, isError: true);
    } catch (e) {
      debugPrint('Profile image error: $e');

      if (!mounted) return;

      setState(() {
        _isUploadingImage = false;
      });

      _showMessage('Profile picture upload failed.', isError: true);
    }
  }

  // ============================================================
  // DONOR AVAILABILITY
  // ============================================================

  Future<void> _changeDonorAvailability(bool value) async {
    final user = _auth.currentUser;

    if (user == null) return;

    try {
      setState(() {
        _donorAvailable = value;
      });

      // Update private user profile
      await _firestore.collection('users').doc(user.uid).set({
        'donorAvailable': value,
      }, SetOptions(merge: true));

      // If user is a donor, update public donor profile
      if (_userType == 'donor') {
        await _firestore.collection('donor_profiles').doc(user.uid).set({
          'userId': user.uid,
          'name': _name,
          'bloodGroup': _bloodGroup,
          'city': _city,
          'country': _country,
          'donorAvailable': value,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      _showMessage(
        value
            ? 'You are now available to donate.'
            : 'You are now unavailable to donate.',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _donorAvailable = !value;
        });
      }

      debugPrint('Donor availability error: $e');

      _showMessage('Could not update availability.', isError: true);
    }
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  Future<void> _changeNotificationSetting(bool value) async {
    setState(() {
      _notificationsEnabled = value;
    });

    await _saveSetting('notificationsEnabled', value);

    // Apply it straight away (live alerts + push).
    if (value) {
      LiveAlerts.resume();
      PushService.init();
    } else {
      LiveAlerts.stop();
      PushService.removeToken();
    }
  }

  // ============================================================
  // SETTINGS
  // ============================================================

  void _showSettings() {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 25),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
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

                const SizedBox(height: 20),

                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),

                const SizedBox(height: 20),

                SwitchListTile(
                  value: _notificationsEnabled,
                  onChanged: (value) {
                    Navigator.pop(context);
                    _changeNotificationSetting(value);
                  },
                  activeColor: Colors.red,
                  secondary: Icon(
                    Icons.notifications_active_outlined,
                    color: colorScheme.primary,
                  ),
                  title: const Text(
                    'Notifications',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Receive blood requests and important alerts',
                  ),
                ),

                _settingsListTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Appearance',
                  subtitle: _appearance,
                  color: colorScheme.primary,
                  onTap: () {
                    Navigator.pop(context);
                    _showAppearanceDialog();
                  },
                ),

                _settingsListTile(
                  icon: Icons.language_outlined,
                  title: 'Language',
                  subtitle: _language,
                  color: colorScheme.primary,
                  onTap: () {
                    Navigator.pop(context);
                    _showLanguageDialog();
                  },
                ),

                _settingsListTile(
                  icon: Icons.accessibility_new_outlined,
                  title: 'Accessibility',
                  subtitle: 'Accessibility options',
                  color: colorScheme.primary,
                  onTap: () {
                    Navigator.pop(context);
                    _showAccessibility();
                  },
                ),

                _settingsListTile(
                  icon: Icons.location_on_outlined,
                  title: 'Location Services',
                  subtitle: 'Find nearby hospitals and labs',
                  color: colorScheme.primary,
                  onTap: () {
                    Navigator.pop(context);
                    _showLocationInfo();
                  },
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _settingsListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        tileColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  // ============================================================
  // APPEARANCE
  // ============================================================

  void _showAppearanceDialog() {
    String selected = _appearance;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Appearance'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'System',
                    groupValue: selected,
                    title: const Text('System Default'),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setDialogState(() {
                        selected = value;
                      });
                    },
                  ),

                  RadioListTile<String>(
                    value: 'Light',
                    groupValue: selected,
                    title: const Text('Light Mode'),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setDialogState(() {
                        selected = value;
                      });
                    },
                  ),

                  RadioListTile<String>(
                    value: 'Dark',
                    groupValue: selected,
                    title: const Text('Dark Mode'),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setDialogState(() {
                        selected = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),

                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);

                    setState(() {
                      _appearance = selected;
                    });

                    widget.themeController.setTheme(selected);

                    await _saveSetting('appearance', selected);

                    _showMessage('Appearance saved.');
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // LANGUAGE
  // ============================================================

  void _showLanguageDialog() {
    showLanguagePicker(
      context,
      onChanged: (name) async {
        if (!mounted) return;

        setState(() {
          _language = name;
        });

        await _saveSetting('language', name);

        _showMessage('$name selected.');
      },
    );
  }

  // ============================================================
  // ACCESSIBILITY
  // ============================================================

  void _showAccessibility() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Accessibility'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accessibility features can include:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('• Larger text'),
              Text('• Better contrast'),
              Text('• Screen reader support'),
              Text('• Larger touch targets'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SAVE SETTING
  // ============================================================

  Future<void> _saveSetting(String field, dynamic value) async {
    final user = _auth.currentUser;

    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).set({
        field: value,
        if (field == 'appearance') 'appearanceChosen': true,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Setting save error: $e');

      _showMessage('Could not save setting.', isError: true);
    }
  }

  // ============================================================
  // LOCATION
  // ============================================================

  void _showLocationInfo() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.red),
              SizedBox(width: 10),
              Text('Location Services'),
            ],
          ),
          content: const Text(
            'BloodConnect can use your location to help you find nearby hospitals, clinics and laboratories.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);

                _showMessage('Location feature will be connected next.');
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // HOW IT WORKS
  // ============================================================

  void _showHowItWorks() {
    _showInfoDialog(
      title: 'How BloodConnect Works',
      content:
          '1. Create your profile.\n\n'
          '2. Add your blood group and location.\n\n'
          '3. Donors can mark themselves available.\n\n'
          '4. Receivers can create blood requests.\n\n'
          '5. Blood donors can respond to requests.\n\n'
          '6. Always verify emergency information before donating.',
    );
  }

  // ============================================================
  // DONATION GUIDE
  // ============================================================

  void _showDonationGuide() {
    _showInfoDialog(
      title: 'Blood Donation Guide',
      content:
          'Before donating:\n\n'
          '• Stay hydrated.\n'
          '• Eat a healthy meal.\n'
          '• Carry valid identification.\n'
          '• Follow the instructions of medical staff.\n\n'
          'After donating:\n\n'
          '• Rest for a while.\n'
          '• Drink fluids.\n'
          '• Follow medical advice.',
    );
  }

  // ============================================================
  // FAQ
  // ============================================================

  void _showFAQ() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
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
                  'Frequently Asked Questions',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),

                const SizedBox(height: 20),

                _faqItem(
                  'How can I become a donor?',
                  'Complete your profile, select your blood group and turn on donor availability.',
                ),

                _faqItem(
                  'How can I request blood?',
                  'Use the blood request feature and provide the required patient and hospital information.',
                ),

                _faqItem(
                  'Can I change my blood group?',
                  'Yes. Open Edit Profile and update your information carefully.',
                ),

                _faqItem(
                  'How do I stop receiving notifications?',
                  'Open Settings and turn off Notifications.',
                ),

                _faqItem(
                  'Is BloodConnect a medical service?',
                  'No. BloodConnect is a platform that helps connect blood donors and people who need blood. Medical decisions should be made by qualified healthcare professionals.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _faqItem(String question, String answer) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        question,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, bottom: 14),
          child: Text(
            answer,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SUPPORT
  // ============================================================

  void _contactSupport() {
    _showInfoDialog(
      title: 'Contact Support',
      content: AppConfig.supportEmail.isEmpty
          ? 'For support, please contact the BloodConnect support team.'
          : 'For support, please contact the BloodConnect support team.\n\n'
                'Email: ${AppConfig.supportEmail}',
    );
  }

  // ============================================================
  // PRIVACY
  // ============================================================

  void _showPrivacyPolicy() {
    _showInfoDialog(
      title: 'Privacy Policy',
      content: LegalTexts.privacyPolicy,
    );
  }

  // ============================================================
  // TERMS
  // ============================================================

  void _showTerms() {
    _showInfoDialog(
      title: 'Terms & Conditions',
      content: LegalTexts.terms,
    );
  }

  // ============================================================
  // DELETE ACCOUNT
  // ============================================================

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Account?'),
          content: const Text(
            'Your BloodConnect account and profile data will be permanently deleted. '
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final user = _auth.currentUser;

    if (user == null) {
      _showMessage('No logged-in account found.', isError: true);
      return;
    }

    final String uid = user.uid;

    try {
      debugPrint('Starting account deletion...');
      debugPrint('User UID: $uid');

      // ============================================================
      // STEP 0: Firebase only allows deleting an account shortly after
      // login. Check this BEFORE deleting any data so the user is never
      // left half-deleted.
      // ============================================================

      final tokenResult = await user.getIdTokenResult(true);
      final authTime = tokenResult.authTime;
      if (authTime == null ||
          DateTime.now().difference(authTime) > const Duration(minutes: 4)) {
        if (!mounted) return;
        _showMessage(
          'For security, please logout, login again, and then delete your account.',
          isError: true,
        );
        return;
      }

      LiveAlerts.stop();
      await PushService.removeToken();

      // ============================================================
      // STEP 1: DELETE FIRESTORE PROFILES FIRST
      // (private profile + public donor profile, in one batch)
      // ============================================================

      final deleteBatch = _firestore.batch();
      deleteBatch.delete(_firestore.collection('users').doc(uid));
      deleteBatch.delete(_firestore.collection('donor_profiles').doc(uid));
      await deleteBatch.commit();

      debugPrint('Firestore profile deleted successfully.');

      // ============================================================
      // STEP 2: DELETE FIREBASE AUTH ACCOUNT
      // ============================================================

      await user.delete();

      debugPrint('Firebase Auth account deleted successfully.');

      // ============================================================
      // STEP 3: GO TO LOGIN SCREEN
      // ============================================================

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(themeController: widget.themeController),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth delete error: ${e.code} - ${e.message}');

      if (!mounted) return;

      if (e.code == 'requires-recent-login') {
        _showMessage(
          'For security, please logout, login again, and then delete your account.',
          isError: true,
        );
      } else {
        _showMessage(e.message ?? 'Unable to delete account.', isError: true);
      }
    } on FirebaseException catch (e) {
      debugPrint('Firestore delete error: ${e.code} - ${e.message}');

      if (!mounted) return;

      _showMessage(
        'Unable to delete your profile. Please try again.',
        isError: true,
      );
    } catch (e) {
      debugPrint('Delete account error: $e');

      if (!mounted) return;

      _showMessage('Unable to delete account.', isError: true);
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    try {
      debugPrint('Logging out...');

      // Stop push notifications for this device before leaving the account.
      LiveAlerts.stop();
      await PushService.removeToken();

      await _auth.signOut();

      debugPrint('Logout complete. Current user: ${_auth.currentUser}');

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => LoginScreen(themeController: widget.themeController),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint('Logout error: ${e.code} - ${e.message}');

      if (!mounted) return;

      _showMessage(e.message ?? 'Logout failed.', isError: true);
    } catch (e) {
      debugPrint('Logout error: $e');

      if (!mounted) return;

      _showMessage('Logout failed.', isError: true);
    }
  }

  // ============================================================
  // COMMON INFO DIALOG
  // ============================================================

  void _showInfoDialog({required String title, required String content}) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Text(content, style: const TextStyle(height: 1.5)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
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

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _showSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),

      body: RefreshIndicator(
        color: Colors.red,
        onRefresh: _loadProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileHeader(),

              const SizedBox(height: 18),

              if (_userType == 'donor') _buildAvailabilityCard(),

              const SizedBox(height: 18),

              _buildSectionTitle('Account'),

              const SizedBox(height: 8),

              _buildMenuCard(
                icon: Icons.edit_outlined,
                title: 'Edit Profile',
                subtitle: 'Update your personal information',
                onTap: _openEditProfile,
              ),

              _buildMenuCard(
                icon: Icons.bloodtype_outlined,
                title: 'Blood Group & Availability',
                subtitle: _userType == 'donor'
                    ? (_donorAvailable
                          ? 'Available to donate'
                          : 'Currently unavailable')
                    : 'Blood group: $_bloodGroup',
                onTap: () {
                  if (_userType == 'donor') {
                    _showAvailabilityDialog();
                  } else {
                    _openEditProfile();
                  }
                },
              ),

              _buildMenuCard(
                icon: Icons.location_on_outlined,
                title: 'Location',
                subtitle: _locationText(),
                onTap: _showLocationInfo,
              ),

              const SizedBox(height: 18),

              _buildSectionTitle('Preferences'),

              const SizedBox(height: 8),

              _buildMenuCard(
                icon: Icons.notifications_none,
                title: 'Notifications',
                subtitle: _notificationsEnabled ? 'Enabled' : 'Disabled',
                trailing: Switch(
                  value: _notificationsEnabled,
                  activeColor: Colors.red,
                  onChanged: _changeNotificationSetting,
                ),
                onTap: () {
                  _changeNotificationSetting(!_notificationsEnabled);
                },
              ),

              _buildMenuCard(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                subtitle: _appearance,
                onTap: _showAppearanceDialog,
              ),

              _buildMenuCard(
                icon: Icons.language_outlined,
                title: 'Language',
                subtitle: _language,
                onTap: _showLanguageDialog,
              ),

              const SizedBox(height: 18),

              _buildSectionTitle('Help & Support'),

              const SizedBox(height: 8),

              _buildMenuCard(
                icon: Icons.info_outline,
                title: 'How BloodConnect Works',
                subtitle: 'Learn how the app works',
                onTap: _showHowItWorks,
              ),

              _buildMenuCard(
                icon: Icons.volunteer_activism_outlined,
                title: 'Donation Guide',
                subtitle: 'Basic blood donation information',
                onTap: _showDonationGuide,
              ),

              _buildMenuCard(
                icon: Icons.help_outline,
                title: 'FAQs',
                subtitle: 'Frequently asked questions',
                onTap: _showFAQ,
              ),

              _buildMenuCard(
                icon: Icons.support_agent_outlined,
                title: 'Contact Support',
                subtitle: 'Get help with BloodConnect',
                onTap: _contactSupport,
              ),

              _buildMenuCard(
                icon: Icons.block_outlined,
                title: 'Blocked Users',
                subtitle: 'Manage people you have blocked',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BlockedUsersScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 18),

              _buildSectionTitle('Legal'),

              const SizedBox(height: 8),

              _buildMenuCard(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                subtitle: 'How your information is handled',
                onTap: _showPrivacyPolicy,
              ),

              _buildMenuCard(
                icon: Icons.description_outlined,
                title: 'Terms & Conditions',
                subtitle: 'BloodConnect terms of use',
                onTap: _showTerms,
              ),

              const SizedBox(height: 22),

              _buildDangerButton(
                icon: Icons.delete_outline,
                title: 'Delete Account',
                onTap: _deleteAccount,
              ),

              const SizedBox(height: 10),

              _buildLogoutButton(),

              const SizedBox(height: 20),

              Center(
                child: Text(
                  'BloodConnect',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PROFILE HEADER
  // ============================================================

  Widget _buildProfileHeader() {
    final isDonor = _userType == 'donor';

    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.2 : 0.05,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 105,
                height: 105,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade100, width: 3),
                ),
                child: ClipOval(child: _buildProfileImage()),
              ),

              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: _changeProfilePicture,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: _isUploadingImage
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Text(
            _name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),

          const SizedBox(height: 5),

          if (_email.isNotEmpty)
            Text(
              _email,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBadge(isDonor ? 'Donor' : 'Receiver'),

              const SizedBox(width: 8),

              _buildBadge(_bloodGroup, icon: Icons.bloodtype),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 17,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),

              const SizedBox(width: 4),

              Flexible(
                child: Text(
                  _locationText(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),

          if (isDonor) ...[
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _donorAvailable
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _donorAvailable ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),

                  const SizedBox(width: 8),

                  Text(
                    _donorAvailable
                        ? 'Available to Donate'
                        : 'Currently Unavailable',
                    style: TextStyle(
                      color: _donorAvailable
                          ? Colors.green.shade700
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // BASE64 IMAGE DISPLAY
  // ============================================================

  Widget _buildProfileImage() {
    if (_profileImageBase64.isEmpty) {
      return const Icon(Icons.person, size: 55, color: Colors.red);
    }

    try {
      final imageBytes = base64Decode(_profileImageBase64);

      return Image.memory(
        imageBytes,
        fit: BoxFit.cover,
        width: 105,
        height: 105,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.person, size: 55, color: Colors.red);
        },
      );
    } catch (e) {
      debugPrint('Base64 image decode error: $e');

      return const Icon(Icons.person, size: 55, color: Colors.red);
    }
  }

  // ============================================================
  // AVAILABILITY CARD
  // ============================================================

  Widget _buildAvailabilityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _donorAvailable ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _donorAvailable ? Colors.green.shade100 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _donorAvailable
                  ? Colors.green.shade100
                  : Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _donorAvailable
                  ? Icons.volunteer_activism
                  : Icons.pause_circle_outline,
              color: _donorAvailable
                  ? Colors.green.shade700
                  : Colors.grey.shade700,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _donorAvailable ? 'You are available' : 'You are unavailable',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  _donorAvailable
                      ? 'People can find you as an available donor.'
                      : 'You will not appear as currently available.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),

          Switch(
            value: _donorAvailable,
            activeColor: Colors.green,
            onChanged: _changeDonorAvailability,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // AVAILABILITY DIALOG
  // ============================================================

  void _showAvailabilityDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Donor Availability'),
          content: const Text(
            'Turn this ON when you are currently available to donate blood.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);

                _changeDonorAvailability(!_donorAvailable);
              },
              child: Text(
                _donorAvailable ? 'Set Unavailable' : 'Set Available',
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // MENU CARD
  // ============================================================

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);

    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: ListTile(
          tileColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 5,
          ),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: Colors.red),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              subtitle,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ),
          trailing:
              trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: onTap,
        ),
      ),
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }

  // ============================================================
  // BADGE
  // ============================================================

  Widget _buildBadge(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: Colors.red),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LOCATION TEXT
  // ============================================================

  String _locationText() {
    if (_city.isNotEmpty && _country.isNotEmpty) {
      return '$_city, $_country';
    }

    if (_city.isNotEmpty) {
      return _city;
    }

    if (_country.isNotEmpty) {
      return _country;
    }

    return 'Location not set';
  }

  // ============================================================
  // DANGER BUTTON
  // ============================================================

  Widget _buildDangerButton({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        label: Text(
          title,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: Colors.red.shade200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // LOGOUT BUTTON
  // ============================================================

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _logout,
        icon: const Icon(Icons.logout),
        label: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }
}
