import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n/app_strings.dart';
import '../l10n/app_text.dart';

import '../services/location_helper.dart';
import 'package:image_picker/image_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();

  String _selectedBloodGroup = 'O+';

  // Base64 image
  String _profileImageBase64 = '';

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

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;

  // Used to keep the public donor profile in sync for donors.
  String _role = '';
  bool _locationShared = false;
  bool _savingLocation = false;

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

      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data() ?? {};

        _role = (data['role'] ?? '').toString().toLowerCase();
        _locationShared = data['locationShared'] == true;

        _nameController.text = (data['name'] ?? '').toString();

        _emailController.text = (data['email'] ?? user.email ?? '').toString();

        _phoneController.text = (data['phone'] ?? '').toString();

        _countryController.text = (data['country'] ?? '').toString();

        _cityController.text = (data['city'] ?? '').toString();
        _areaController.text = (data['area'] ?? '').toString();

        // ========================================================
        // LOAD BASE64 PROFILE IMAGE
        // ========================================================

        _profileImageBase64 = (data['profileImageBase64'] ?? '').toString();

        final bloodGroup = (data['bloodGroup'] ?? 'O+').toString();

        if (_bloodGroups.contains(bloodGroup)) {
          _selectedBloodGroup = bloodGroup;
        }
      } else {
        _emailController.text = user.email ?? '';
      }

      setState(() {
        _isLoading = false;
      });
    } on FirebaseException catch (e) {
      debugPrint('Profile loading Firebase error: ${e.code} - ${e.message}');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      if (e.code == 'permission-denied') {
        _showMessage(
          'Permission denied. Please check Firestore Rules.',
          isError: true,
        );
      } else {
        _showMessage(
          'Unable to load your profile. Please try again.',
          isError: true,
        );
      }
    } catch (e) {
      debugPrint('Profile loading error: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        'Unable to load your profile. Please try again.',
        isError: true,
      );
    }
  }

  // ============================================================
  // CHANGE PROFILE PICTURE
  // ============================================================

  Future<void> _changeProfilePicture() async {
    if (_isUploadingImage) return;

    final user = _auth.currentUser;

    if (user == null) {
      _showMessage('User session expired. Please login again.', isError: true);
      return;
    }

    try {
      // ----------------------------------------------------------
      // PICK IMAGE
      // ----------------------------------------------------------

      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 55,
        maxWidth: 500,
        maxHeight: 500,
      );

      if (image == null) {
        return;
      }

      if (!mounted) return;

      setState(() {
        _isUploadingImage = true;
      });

      // ----------------------------------------------------------
      // READ IMAGE
      // ----------------------------------------------------------

      final Uint8List bytes = await image.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('Selected image is empty.');
      }

      debugPrint('Selected image size: ${bytes.length} bytes');

      // ----------------------------------------------------------
      // CONVERT TO BASE64
      // ----------------------------------------------------------

      final String base64Image = base64Encode(bytes);

      debugPrint('Base64 image length: ${base64Image.length}');

      // ----------------------------------------------------------
      // SAVE BASE64 TO FIRESTORE
      // ----------------------------------------------------------

      await _firestore.collection('users').doc(user.uid).set({
        'profileImageBase64': base64Image,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('Base64 profile image saved to Firestore.');

      if (!mounted) return;

      setState(() {
        _profileImageBase64 = base64Image;
        _isUploadingImage = false;
      });

      _showMessage('Profile picture updated successfully.');
    } on FirebaseException catch (e) {
      debugPrint('Firebase profile image error: ${e.code} - ${e.message}');

      if (!mounted) return;

      setState(() {
        _isUploadingImage = false;
      });

      String message;

      switch (e.code) {
        case 'permission-denied':
          message = 'Permission denied. Please check Firestore Rules.';
          break;

        case 'resource-exhausted':
          message = 'Image is too large. Please choose a smaller picture.';
          break;

        case 'network-request-failed':
          message = 'Network error. Please check your internet connection.';
          break;

        case 'unavailable':
          message = 'Firebase is temporarily unavailable. Please try again.';
          break;

        default:
          message = 'Image upload failed: ${e.message ?? e.code}';
      }

      _showMessage(message, isError: true);
    } catch (e) {
      debugPrint('Profile image upload error: $e');

      if (!mounted) return;

      setState(() {
        _isUploadingImage = false;
      });

      _showMessage(
        'Profile picture upload failed. Please try again.',
        isError: true,
      );
    }
  }

  // ============================================================
  // BUILD PROFILE IMAGE
  // ============================================================

  Widget _buildProfileImage() {
    if (_profileImageBase64.isEmpty) {
      return const Icon(Icons.person_rounded, color: Colors.white, size: 55);
    }

    try {
      final Uint8List imageBytes = base64Decode(_profileImageBase64);

      return Image.memory(
        imageBytes,
        width: 110,
        height: 110,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Edit profile image decode error: $error');

          return const Icon(
            Icons.person_rounded,
            color: Colors.white,
            size: 55,
          );
        },
      );
    } catch (e) {
      debugPrint('Base64 image decode error: $e');

      return const Icon(Icons.person_rounded, color: Colors.white, size: 55);
    }
  }

  // ============================================================
  // SAVE PROFILE
  // ============================================================

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = _auth.currentUser;

    if (user == null) {
      _showMessage('User session expired. Please login again.', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final saveBatch = _firestore.batch();

      saveBatch.set(_firestore.collection('users').doc(user.uid), {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'country': _countryController.text.trim(),
        'city': _cityController.text.trim(),
        'area': _areaController.text.trim(),
        'bloodGroup': _selectedBloodGroup,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Donors are found through donor_profiles, so it must stay in sync.
      // (Phone and email are never copied there - they stay private.)
      if (_role == 'donor') {
        saveBatch.set(_firestore.collection('donor_profiles').doc(user.uid), {
          'userId': user.uid,
          'name': _nameController.text.trim(),
          'country': _countryController.text.trim(),
          'city': _cityController.text.trim(),
          'area': _areaController.text.trim(),
          'bloodGroup': _selectedBloodGroup,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await saveBatch.commit();

      if (!mounted) return;

      _showMessage('Profile updated successfully.');

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      debugPrint('Profile save Firebase error: ${e.code} - ${e.message}');

      if (!mounted) return;

      if (e.code == 'permission-denied') {
        _showMessage(
          'Permission denied. Please check Firestore Rules.',
          isError: true,
        );
      } else {
        _showMessage(
          'Failed to update profile. Please try again.',
          isError: true,
        );
      }
    } catch (e) {
      debugPrint('Profile save error: $e');

      if (!mounted) return;

      _showMessage(
        'Failed to update profile. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
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
  // APPROXIMATE LOCATION (DONOR, OPT-IN)
  // ============================================================

  Future<void> _shareApproxLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _savingLocation = true);

    final result = await LocationHelper.getApproximate();
    if (!mounted) return;

    if (result.error != null) {
      setState(() => _savingLocation = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }

    try {
      final batch = _firestore.batch();
      batch.set(_firestore.collection('donor_profiles').doc(user.uid), {
        'userId': user.uid,
        'latitude': result.latitude,
        'longitude': result.longitude,
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(_firestore.collection('users').doc(user.uid), {
        'locationShared': true,
      }, SetOptions(merge: true));
      await batch.commit();

      if (!mounted) return;
      setState(() {
        _locationShared = true;
        _savingLocation = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your location.')),
      );
    }
  }

  Future<void> _stopSharingLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _savingLocation = true);

    try {
      final batch = _firestore.batch();
      batch.set(_firestore.collection('donor_profiles').doc(user.uid), {
        'userId': user.uid,
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'locationUpdatedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(_firestore.collection('users').doc(user.uid), {
        'locationShared': false,
      }, SetOptions(merge: true));
      await batch.commit();

      if (!mounted) return;
      setState(() {
        _locationShared = false;
        _savingLocation = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not stop sharing. Try again.')),
      );
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    _cityController.dispose();
    _areaController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),

      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Color(0xFF171717),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          onPressed: _isSaving || _isUploadingImage
              ? null
              : () {
                  Navigator.pop(context);
                },
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF171717)),
        ),
      ),

      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE53935)),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 35),
                child: Column(
                  children: [
                    // ==================================================
                    // PROFILE PICTURE
                    // ==================================================

                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ClipOval(child: _buildProfileImage()),
                        ),

                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53935),
                            shape: BoxShape.circle,
                          ),
                          child: _isUploadingImage
                              ? const Padding(
                                  padding: EdgeInsets.all(9),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : IconButton(
                                  onPressed: _changeProfilePicture,
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.camera_alt_outlined,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                                ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    TextButton.icon(
                      onPressed: _isUploadingImage
                          ? null
                          : _changeProfilePicture,
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: Text(
                        _isUploadingImage ? 'Saving...' : 'Change Photo',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE53935),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ==================================================
                    // FULL NAME
                    // ==================================================
                    _buildTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      hint: 'Enter your full name',
                      icon: Icons.person_outline_rounded,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppStrings.tr('Please enter your name');
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // EMAIL
                    // ==================================================
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email Address',
                      hint: 'Enter your email',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppStrings.tr('Please enter your email');
                        }

                        if (!value.contains('@')) {
                          return AppStrings.tr('Enter a valid email address');
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // PHONE
                    // ==================================================
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      hint: 'e.g. +92 300 1234567',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppStrings.tr('Please enter your phone number');
                        }

                        if (value.trim().length < 7) {
                          return AppStrings.tr('Enter a valid phone number');
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // COUNTRY
                    // ==================================================
                    _buildTextField(
                      controller: _countryController,
                      label: 'Country',
                      hint: 'e.g. Pakistan, UAE, UK',
                      icon: Icons.public_rounded,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppStrings.tr('Please enter your country');
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // CITY
                    // ==================================================
                    _buildTextField(
                      controller: _cityController,
                      label: 'City',
                      hint: 'e.g. Lahore',
                      icon: Icons.location_city_outlined,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return AppStrings.tr('Please enter your city');
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // AREA (OPTIONAL)
                    // ==================================================
                    _buildTextField(
                      controller: _areaController,
                      label: 'Area (optional)',
                      hint: 'e.g. Johar Town',
                      icon: Icons.location_on_outlined,
                      validator: (value) => null,
                    ),

                    const SizedBox(height: 16),

                    // ==================================================
                    // APPROXIMATE LOCATION (DONORS, OPTIONAL)
                    // ==================================================
                    if (_role == 'donor') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _locationShared
                                  ? 'Approximate location is shared (about 1 km accuracy). Receivers can sort donors by distance.'
                                  : 'Optional: share your approximate location (about 1 km accuracy) so nearby receivers can find you. Your exact position is never saved.',
                              style: const TextStyle(fontSize: 12.5, height: 1.4),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _savingLocation
                                      ? null
                                      : _shareApproxLocation,
                                  icon: const Icon(Icons.my_location, size: 18),
                                  label: Text(
                                    _locationShared
                                        ? 'Update location'
                                        : 'Share approximate location',
                                  ),
                                ),
                                if (_locationShared)
                                  TextButton(
                                    onPressed: _savingLocation
                                        ? null
                                        : _stopSharingLocation,
                                    child: const Text('Stop sharing'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],

                    // ==================================================
                    // BLOOD GROUP
                    // ==================================================
                    _buildBloodGroupDropdown(),

                    const SizedBox(height: 30),

                    // ==================================================
                    // SAVE
                    // ==================================================
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isSaving || _isUploadingImage
                            ? null
                            : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade400,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
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
  // TEXT FIELD
  // ============================================================

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF444444),
          ),
        ),

        const SizedBox(height: 8),

        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: AppStrings.tr(hint),
            prefixIcon: Icon(icon, color: const Color(0xFFE53935)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFE53935),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.red),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BLOOD GROUP
  // ============================================================

  Widget _buildBloodGroupDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Blood Group',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF444444),
          ),
        ),

        const SizedBox(height: 8),

        DropdownButtonFormField<String>(
          initialValue: _selectedBloodGroup,
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.bloodtype_outlined,
              color: Color(0xFFE53935),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
            ),
          ),
          items: _bloodGroups.map((group) {
            return DropdownMenuItem<String>(value: group, child: Text(group));
          }).toList(),
          onChanged: _isSaving || _isUploadingImage
              ? null
              : (value) {
                  if (value == null) return;

                  setState(() {
                    _selectedBloodGroup = value;
                  });
                },
        ),
      ],
    );
  }
}
