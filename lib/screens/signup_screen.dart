import 'package:flutter/material.dart' hide Text;
import '../l10n/app_strings.dart';
import '../l10n/app_text.dart';
import '../l10n/language_picker.dart';

import '../config/countries.dart';
import 'legal_texts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme_controller.dart';
import 'donor_dashboard_screen.dart';
import 'receiver_dashboard_screen.dart';

class SignupScreen extends StatefulWidget {
  final ThemeController themeController;

  const SignupScreen({super.key, required this.themeController});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  String _selectedCountry = 'Pakistan';
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

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

  String? _selectedBloodGroup;

  bool _isDonor = true;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _isLoading = false;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    _areaController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ============================================================
  // CREATE ACCOUNT
  // ============================================================

  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the Terms & Conditions and Privacy Policy to continue.',
          ),
          backgroundColor: Color(0xFFD62839),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // ==========================================================
      // CREATE FIREBASE AUTH ACCOUNT
      // ==========================================================

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      final user = credential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-created',
          message: 'Account could not be created.',
        );
      }

      final firestore = FirebaseFirestore.instance;

      // ==========================================================
      // USER DATA
      // ==========================================================

      final String name = _nameController.text.trim();
      final String email = _emailController.text.trim();
      final String phone = _phoneController.text.trim();
      final String city = _cityController.text.trim();
      final String area = _areaController.text.trim();
      final String bloodGroup = _selectedBloodGroup!;

      final String role = _isDonor ? 'donor' : 'receiver';

      // ==========================================================
      // CREATE PROFILE DOCUMENTS (ONE ATOMIC BATCH)
      // If this fails, the Auth account is removed again so the user
      // is never left with a login but no profile.
      // ==========================================================

      final writeBatch = firestore.batch();

      writeBatch.set(firestore.collection('users').doc(user.uid), {
        'name': name,
        'email': email,
        'phone': phone,
        'city': city,
        'area': area,
        'country': _selectedCountry,
        'bloodGroup': bloodGroup,
        'role': role,

        // Donor availability
        'donorAvailable': _isDonor,

        // Account status
        'isActive': true,

        // Profile
        'profileImageUrl': '',
        'profileImageBase64': '',

        // Settings
        'notificationsEnabled': true,
        'appearance': 'Light',
        'language': 'English',

        // Consent
        'consentAcceptedAt': FieldValue.serverTimestamp(),
        'consentVersion': '1.0',

        // Timestamps
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ==========================================================
      // CREATE DONOR PROFILE
      // Public searchable profile: phone and email are intentionally
      // NOT stored here (they stay private in users/{uid}).
      // ==========================================================

      if (_isDonor) {
        writeBatch.set(firestore.collection('donor_profiles').doc(user.uid), {
          'userId': user.uid,

          'name': name,

          'city': city,
          'area': area,
          'country': _selectedCountry,

          'bloodGroup': bloodGroup,

          // Donor availability
          'donorAvailable': true,

          // Account status
          'isActive': true,

          // Profile image
          'profileImageUrl': '',
          'profileImageBase64': '',

          // Timestamps
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      try {
        await writeBatch.commit();
      } catch (_) {
        try {
          await user.delete();
        } catch (_) {}
        rethrow;
      }

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // ==========================================================
      // DONOR → DONOR DASHBOARD
      // ==========================================================

      if (_isDonor) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) =>
                DonorDashboardScreen(themeController: widget.themeController),
          ),
          (route) => false,
        );
      }
      // ==========================================================
      // RECEIVER → RECEIVER DASHBOARD
      // ==========================================================
      else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => ReceiverDashboardScreen(
              themeController: widget.themeController,
            ),
          ),
          (route) => false,
        );
      }
    }
    // ============================================================
    // FIREBASE AUTH ERRORS
    // ============================================================
    on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email is already registered.';
          break;

        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;

        case 'weak-password':
          message = 'Password is too weak. Use at least 8 characters.';
          break;

        case 'operation-not-allowed':
          message = 'Email/Password sign-up is not enabled in Firebase.';
          break;

        case 'network-request-failed':
          message = 'Network error. Please check your internet connection.';
          break;

        default:
          message = e.message ?? 'Something went wrong. Please try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFD62839),
        ),
      );
    }
    // ============================================================
    // OTHER ERRORS
    // ============================================================
    catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      debugPrint('Signup error: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: Color(0xFFD62839),
        ),
      );
    }
  }

  // ============================================================
  // LEGAL TEXT DIALOG
  // ============================================================

  void _showLegalDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Text(content, style: const TextStyle(height: 1.5)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // INPUT DECORATION
  // ============================================================

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InputDecoration(
      hintText: AppStrings.tr(hintText),

      prefixIcon: Icon(icon, color: const Color(0xFFD62839)),

      suffixIcon: suffixIcon,

      filled: true,

      fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,

      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD62839), width: 1.5),
      ),

      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD62839)),
      ),

      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD62839), width: 1.5),
      ),
    );
  }

  // ============================================================
  // FIELD LABEL
  // ============================================================

  Widget _label(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : const Color(0xFF333333),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF101010)
          : const Color(0xFFFDF8F8),

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,

        leading: IconButton(
          onPressed: _isLoading
              ? null
              : () {
                  Navigator.pop(context);
                },
          icon: const Icon(Icons.arrow_back_rounded),
          color: isDark ? Colors.white : const Color(0xFF222222),
        ),
        actions: const [LanguageButton(), SizedBox(width: 8)],
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 35),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ==================================================
                // TITLE
                // ==================================================

                Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF222222),
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Create your BloodConnect account and help save lives.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: isDark ? Colors.white70 : const Color(0xFF777777),
                  ),
                ),

                const SizedBox(height: 30),

                // ==================================================
                // FULL NAME
                // ==================================================
                _label('Full Name'),

                TextFormField(
                  controller: _nameController,
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,

                  decoration: _inputDecoration(
                    hintText: 'Enter your full name',
                    icon: Icons.person_outline_rounded,
                  ),

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.tr('Please enter your name');
                    }

                    if (value.trim().length < 3) {
                      return AppStrings.tr('Name must be at least 3 characters');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // ==================================================
                // EMAIL
                // ==================================================
                _label('Email Address'),

                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,

                  decoration: _inputDecoration(
                    hintText: 'Enter your email',
                    icon: Icons.email_outlined,
                  ),

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.tr('Please enter your email');
                    }

                    final RegExp emailRegex = RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    );

                    if (!emailRegex.hasMatch(value.trim())) {
                      return AppStrings.tr('Enter a valid email address');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // ==================================================
                // PHONE
                // ==================================================
                _label('Phone Number'),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,

                  decoration: _inputDecoration(
                    hintText: 'e.g. +92 300 1234567',
                    icon: Icons.phone_outlined,
                  ),

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.tr('Please enter your phone number');
                    }

                    // International numbers: optional +, digits, spaces, - ( )
                    final text = value.trim();
                    final digits = text.replaceAll(RegExp(r'\D'), '');
                    final validChars = RegExp(r'^\+?[0-9\s\-()]+$');

                    if (!validChars.hasMatch(text) ||
                        digits.length < 7 ||
                        digits.length > 15) {
                      return AppStrings.tr('Enter a valid phone number');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // ==================================================
                // COUNTRY
                // ==================================================
                _label('Country'),

                DropdownButtonFormField<String>(
                  initialValue: _selectedCountry,
                  isExpanded: true,
                  decoration: _inputDecoration(
                    hintText: 'Select your country',
                    icon: Icons.public_rounded,
                  ),
                  items: kCountries.map((country) {
                    return DropdownMenuItem<String>(
                      value: country,
                      child: Text(
                        country,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedCountry = value;
                    });
                  },
                ),

                const SizedBox(height: 20),

                // ==================================================
                // CITY
                // ==================================================
                _label('City'),

                TextFormField(
                  controller: _cityController,
                  keyboardType: TextInputType.streetAddress,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,

                  decoration: _inputDecoration(
                    hintText: 'e.g. Lahore',
                    icon: Icons.location_city_outlined,
                  ),

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.tr('Please enter your city');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // ==================================================
                // AREA (OPTIONAL)
                // ==================================================
                _label('Area (optional)'),

                TextFormField(
                  controller: _areaController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,

                  decoration: _inputDecoration(
                    hintText: 'e.g. Johar Town',
                    icon: Icons.location_on_outlined,
                  ),
                ),

                const SizedBox(height: 20),

                // ==================================================
                // BLOOD GROUP
                // ==================================================
                _label('Blood Group'),

                DropdownButtonFormField<String>(
                  initialValue: _selectedBloodGroup,

                  isExpanded: true,

                  decoration: _inputDecoration(
                    hintText: 'Select your blood group',
                    icon: Icons.bloodtype_rounded,
                  ),

                  items: _bloodGroups.map((group) {
                    return DropdownMenuItem<String>(
                      value: group,
                      child: Text(
                        group,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    );
                  }).toList(),

                  onChanged: (value) {
                    setState(() {
                      _selectedBloodGroup = value;
                    });
                  },

                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.tr('Please select your blood group');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // ==================================================
                // ROLE
                // ==================================================
                _label('I want to'),

                Row(
                  children: [
                    Expanded(
                      child: _RoleButton(
                        title: 'Donate Blood',
                        icon: Icons.volunteer_activism_rounded,
                        selected: _isDonor,
                        onTap: () {
                          setState(() {
                            _isDonor = true;
                          });
                        },
                      ),
                    ),

                    const SizedBox(width: 12),

                    Expanded(
                      child: _RoleButton(
                        title: 'Find Blood',
                        icon: Icons.search_rounded,
                        selected: !_isDonor,
                        onTap: () {
                          setState(() {
                            _isDonor = false;
                          });
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ==================================================
                // PASSWORD
                // ==================================================
                _label('Password'),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _hidePassword,
                  textInputAction: TextInputAction.next,

                  decoration: _inputDecoration(
                    hintText: 'Create a password',
                    icon: Icons.lock_outline_rounded,

                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _hidePassword = !_hidePassword;
                        });
                      },

                      icon: Icon(
                        _hidePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF888888),
                      ),
                    ),
                  ),

                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.tr('Please create a password');
                    }

                    if (value.length < 8) {
                      return AppStrings.tr('Password must be at least 8 characters');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 20),

                // ==================================================
                // CONFIRM PASSWORD
                // ==================================================
                _label('Confirm Password'),

                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _hideConfirmPassword,
                  textInputAction: TextInputAction.done,

                  onFieldSubmitted: (_) {
                    if (!_isLoading) {
                      _createAccount();
                    }
                  },

                  decoration: _inputDecoration(
                    hintText: 'Confirm your password',
                    icon: Icons.lock_reset_outlined,

                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _hideConfirmPassword = !_hideConfirmPassword;
                        });
                      },

                      icon: Icon(
                        _hideConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF888888),
                      ),
                    ),
                  ),

                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.tr('Please confirm your password');
                    }

                    if (value != _passwordController.text) {
                      return AppStrings.tr('Passwords do not match');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 18),

                // ==================================================
                // CONSENT
                // ==================================================
                InkWell(
                  onTap: () {
                    setState(() {
                      _acceptedTerms = !_acceptedTerms;
                    });
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _acceptedTerms,
                        activeColor: const Color(0xFFD62839),
                        onChanged: (value) {
                          setState(() {
                            _acceptedTerms = value ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'I agree to the Terms & Conditions and Privacy Policy, and I understand that BloodConnect only connects people and does not replace medical advice or emergency services.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _showLegalDialog(
                        'Terms & Conditions',
                        LegalTexts.terms,
                      ),
                      child: const Text('Read Terms'),
                    ),
                    TextButton(
                      onPressed: () => _showLegalDialog(
                        'Privacy Policy',
                        LegalTexts.privacyPolicy,
                      ),
                      child: const Text('Read Privacy Policy'),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ==================================================
                // CREATE ACCOUNT BUTTON
                // ==================================================
                SizedBox(
                  width: double.infinity,
                  height: 56,

                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createAccount,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD62839),

                      foregroundColor: Colors.white,

                      disabledBackgroundColor: const Color(0xFFE7A0A6),

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),

                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // ==================================================
                // LOGIN
                // ==================================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF777777),
                      ),
                    ),

                    GestureDetector(
                      onTap: _isLoading
                          ? null
                          : () {
                              Navigator.pop(context);
                            },

                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFD62839),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// ROLE BUTTON
// ================================================================

class _RoleButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleButton({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,

      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),

          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),

          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF3A171A) : const Color(0xFFFFE8EA))
                : (isDark ? const Color(0xFF1E1E1E) : Colors.white),

            borderRadius: BorderRadius.circular(14),

            border: Border.all(
              color: selected
                  ? const Color(0xFFD62839)
                  : (isDark
                        ? const Color(0xFF333333)
                        : const Color(0xFFE5E5E5)),

              width: selected ? 1.5 : 1,
            ),
          ),

          child: Column(
            children: [
              Icon(
                icon,
                size: 27,

                color: selected
                    ? const Color(0xFFD62839)
                    : (isDark ? Colors.white60 : const Color(0xFF888888)),
              ),

              const SizedBox(height: 8),

              Text(
                title,
                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,

                  color: selected
                      ? const Color(0xFFD62839)
                      : (isDark ? Colors.white70 : const Color(0xFF666666)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
