import 'package:flutter/material.dart' hide Text;
import '../l10n/app_strings.dart';
import '../l10n/app_text.dart';
import '../l10n/language_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/account_gate.dart';
import '../theme_controller.dart';
import 'email_otp_screen.dart';
import 'signup_screen.dart';
import 'donor_dashboard_screen.dart';
import 'receiver_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  final ThemeController themeController;

  const LoginScreen({super.key, required this.themeController});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = credential.user;

      // Administrator accounts have their own login (the admin website).
      if (user != null) {
        final tokenResult = await user.getIdTokenResult();
        if (tokenResult.claims?['admin'] == true) {
          await FirebaseAuth.instance.signOut();
          throw FirebaseAuthException(
            code: 'admin-account',
            message: 'Admin accounts sign in on the admin website.',
          );
        }
      }

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'User account could not be found.',
        );
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        throw FirebaseAuthException(
          code: 'profile-not-found',
          message: 'User profile not found.',
        );
      }

      final data = userDoc.data();
      final role = data?['role'];

      // Suspended accounts are signed out straight away.
      if (await AccountGate.isSuspended(user.uid, data)) {
        await FirebaseAuth.instance.signOut();
        throw FirebaseAuthException(
          code: 'account-suspended',
          message: 'This account has been suspended.',
        );
      }

      AccountGate.touchLastActive(user.uid);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      // OPTIONAL SECOND STEP: 6-digit code sent to the user's email.
      // (Off by default - see AppConfig.emailOtpEnabled.)
      if (AppConfig.emailOtpEnabled && (role == 'donor' || role == 'receiver')) {
        final verified = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => EmailOtpScreen(email: user.email ?? ''),
          ),
        );

        if (verified != true) {
          await FirebaseAuth.instance.signOut();
          return;
        }

        if (!mounted) return;
      }

      // DONOR
      if (role == 'donor') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) =>
                DonorDashboardScreen(themeController: widget.themeController),
          ),
          (route) => false,
        );
      }
      // RECEIVER
      else if (role == 'receiver') {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => ReceiverDashboardScreen(
              themeController: widget.themeController,
            ),
          ),
          (route) => false,
        );
      }
      // INVALID ROLE
      else {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid user role. Please contact support.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      String message;

      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;

        case 'wrong-password':
        case 'invalid-credential':
          message = 'Incorrect email or password.';
          break;

        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;

        case 'user-disabled':
          message = 'This account has been disabled.';
          break;

        case 'profile-not-found':
          message = 'User profile not found in database.';
          break;

        case 'admin-account':
          message =
              'This is an administrator account. Please use the Admin Login on the admin website.';
          break;

        case 'account-suspended':
          message =
              'This account has been suspended. Please contact support.';
          break;

        case 'too-many-requests':
          message = 'Too many login attempts. Please try again later.';
          break;

        case 'network-request-failed':
          message = 'Network error. Please check your internet connection.';
          break;

        default:
          message = e.message ?? 'Login failed. Please try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFD62839),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: Color(0xFFD62839),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your email address first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address.'),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset link has been sent to your email.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;

        case 'user-not-found':
          message = 'No account found with this email.';
          break;

        default:
          message = e.message ?? 'Could not send reset email.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFD62839),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: Color(0xFFD62839),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SignupScreen(themeController: widget.themeController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF101010)
          : const Color(0xFFFDF8F8),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),

          child: Form(
            key: _formKey,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),

                      icon: const Icon(Icons.arrow_back_rounded),

                      color: isDark ? Colors.white : const Color(0xFF222222),

                      padding: EdgeInsets.zero,

                      alignment: Alignment.centerLeft,
                    ),
                    const LanguageButton(),
                  ],
                ),

                const SizedBox(height: 30),

                Text(
                  'Welcome Back',

                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF222222),
                    letterSpacing: -0.7,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Sign in to continue helping save lives.',

                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: isDark ? Colors.white70 : const Color(0xFF777777),
                  ),
                ),

                const SizedBox(height: 38),

                Text(
                  'Email Address',

                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF333333),
                  ),
                ),

                const SizedBox(height: 9),

                TextFormField(
                  controller: _emailController,

                  keyboardType: TextInputType.emailAddress,

                  textInputAction: TextInputAction.next,

                  decoration: InputDecoration(
                    hintText: AppStrings.tr('Enter your email'),

                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Color(0xFFD62839),
                    ),

                    filled: true,

                    fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF333333)
                            : const Color(0xFFEDEDED),
                      ),
                    ),

                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFD62839),
                        width: 1.5,
                      ),
                    ),
                  ),

                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppStrings.tr('Please enter your email');
                    }

                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

                    if (!emailRegex.hasMatch(value.trim())) {
                      return AppStrings.tr('Please enter a valid email');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 22),

                Text(
                  'Password',

                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF333333),
                  ),
                ),

                const SizedBox(height: 9),

                TextFormField(
                  controller: _passwordController,

                  obscureText: _obscurePassword,

                  textInputAction: TextInputAction.done,

                  onFieldSubmitted: (_) => _login(),

                  decoration: InputDecoration(
                    hintText: AppStrings.tr('Enter your password'),

                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFFD62839),
                    ),

                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },

                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,

                        color: const Color(0xFF888888),
                      ),
                    ),

                    filled: true,

                    fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),

                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: isDark
                            ? const Color(0xFF333333)
                            : const Color(0xFFEDEDED),
                      ),
                    ),

                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFD62839),
                        width: 1.5,
                      ),
                    ),
                  ),

                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return AppStrings.tr('Please enter your password');
                    }

                    if (value.length < 6) {
                      return AppStrings.tr('Password must be at least 6 characters');
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerRight,

                  child: TextButton(
                    onPressed: _resetPassword,

                    child: const Text(
                      'Forgot Password?',

                      style: TextStyle(
                        color: Color(0xFFD62839),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 56,

                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD62839),

                      foregroundColor: Colors.white,

                      disabledBackgroundColor: const Color(0xFFE9A0A7),

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
                            'Login',

                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: isDark
                            ? const Color(0xFF333333)
                            : Colors.grey.shade300,
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),

                      child: Text(
                        'OR',

                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white54
                              : const Color(0xFF999999),
                        ),
                      ),
                    ),

                    Expanded(
                      child: Divider(
                        color: isDark
                            ? const Color(0xFF333333)
                            : Colors.grey.shade300,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 26),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,

                  children: [
                    Text(
                      "Don't have an account? ",

                      style: TextStyle(
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF777777),
                        fontSize: 14,
                      ),
                    ),

                    GestureDetector(
                      onTap: _openSignup,

                      child: const Text(
                        'Create Account',

                        style: TextStyle(
                          color: Color(0xFFD62839),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Separate login for administrators (opens the admin website).
                Center(
                  child: TextButton.icon(
                    onPressed: _openAdminLogin,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Admin Login'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAdminLogin() async {
    final opened = await launchUrl(
      Uri.parse(AppConfig.adminPanelUrl),
      mode: LaunchMode.externalApplication,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the admin website.')),
      );
    }
  }
}
