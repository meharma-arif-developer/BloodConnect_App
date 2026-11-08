import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n/app_text.dart';

import 'onboarding_screen.dart';
import 'donor_dashboard_screen.dart';
import 'receiver_dashboard_screen.dart';
import '../l10n/language_controller.dart';
import '../services/account_gate.dart';
import '../theme_controller.dart';

class SplashScreen extends StatefulWidget {
  final ThemeController themeController;

  const SplashScreen({super.key, required this.themeController});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;
  late AnimationController _loadingController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _logoAnimation;
  late Animation<double> _textAnimation;

  @override
  void initState() {
    super.initState();

    // ==========================================================
    // MAIN ANIMATION
    // ==========================================================

    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _mainController,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _logoAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
      ),
    );

    _textAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.35, 0.85, curve: Curves.easeOut),
      ),
    );

    // ==========================================================
    // LOGO PULSE
    // ==========================================================

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // ==========================================================
    // LOADING
    // ==========================================================

    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _mainController.forward();
    _pulseController.repeat(reverse: true);

    // ==========================================================
    // START SESSION CHECK
    // ==========================================================

    Timer(const Duration(milliseconds: 2800), () {
      if (mounted) {
        _checkUserSession();
      }
    });
  }

  // ============================================================
  // CHECK USER SESSION
  // ============================================================

  Future<void> _checkUserSession() async {
    final user = FirebaseAuth.instance.currentUser;

    // ----------------------------------------------------------
    // NO USER
    // ----------------------------------------------------------

    if (user == null) {
      _goToOnboarding();
      return;
    }

    try {
      // --------------------------------------------------------
      // LOAD USER DOCUMENT
      // --------------------------------------------------------

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      // --------------------------------------------------------
      // USER PROFILE DOES NOT EXIST
      // --------------------------------------------------------

      if (!doc.exists) {
        await FirebaseAuth.instance.signOut();
        _goToOnboarding();
        return;
      }

      final data = doc.data() ?? {};

      // ========================================================
      // SUSPENDED ACCOUNTS CANNOT ENTER
      // ========================================================

      if (await AccountGate.isSuspended(user.uid, data)) {
        await FirebaseAuth.instance.signOut();
        _goToOnboarding();
        return;
      }

      AccountGate.touchLastActive(user.uid);
      LanguageController.instance.setByName(data['language']?.toString());

      // ========================================================
      // LOAD SAVED APPEARANCE
      // Light is the default. "System Default" is only used when the
      // user chose it on purpose in Settings.
      // ========================================================

      var appearance = data['appearance']?.toString() ?? 'Light';
      if (appearance == 'System Default' && data['appearanceChosen'] != true) {
        appearance = 'Light';
      }

      // Apply saved appearance BEFORE opening dashboard.
      widget.themeController.setTheme(appearance);

      // ========================================================
      // GET USER ROLE
      // ========================================================

      final role = data['role']?.toString().toLowerCase();

      // ========================================================
      // DONOR
      // ========================================================

      if (role == 'donor') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) =>
                DonorDashboardScreen(themeController: widget.themeController),
          ),
        );

        return;
      }

      // ========================================================
      // RECEIVER
      // ========================================================

      if (role == 'receiver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ReceiverDashboardScreen(
              themeController: widget.themeController,
            ),
          ),
        );

        return;
      }

      // ========================================================
      // INVALID ROLE
      // ========================================================

      await FirebaseAuth.instance.signOut();
      _goToOnboarding();
    } catch (e) {
      debugPrint('Session check error: $e');

      if (!mounted) return;

      _goToOnboarding();
    }
  }

  // ============================================================
  // GO TO ONBOARDING
  // ============================================================

  void _goToOnboarding() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OnboardingScreen(themeController: widget.themeController),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    _loadingController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool isDark = theme.brightness == Brightness.dark;

    final Color backgroundColor = isDark
        ? const Color(0xFF090909)
        : const Color(0xFFFCFAFA);

    final Color primaryRed = const Color(0xFFD62839);

    final Color titleColor = isDark ? Colors.white : const Color(0xFF171717);

    final Color subtitleColor = isDark
        ? Colors.white70
        : const Color(0xFF777777);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // ======================================================
          // BACKGROUND GLOW - TOP RIGHT
          // ======================================================

          Positioned(
            top: -170,
            right: -140,
            child: _buildGlow(
              size: 390,
              color: primaryRed,
              opacity: isDark ? 0.09 : 0.055,
            ),
          ),

          // ======================================================
          // BACKGROUND GLOW - BOTTOM LEFT
          // ======================================================
          Positioned(
            bottom: -190,
            left: -160,
            child: _buildGlow(
              size: 430,
              color: primaryRed,
              opacity: isDark ? 0.07 : 0.045,
            ),
          ),

          // ======================================================
          // CENTER CONTENT
          // ======================================================
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ==================================================
                    // PREMIUM LOGO
                    // ==================================================

                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final pulse = _pulseController.value;

                        return Transform.scale(
                          scale: 1.0 + (pulse * 0.025),
                          child: Container(
                            width: 126,
                            height: 126,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: primaryRed.withValues(
                                    alpha: 0.12 + (pulse * 0.10),
                                  ),
                                  blurRadius: 35 + (pulse * 12),
                                  spreadRadius: 2 + (pulse * 3),
                                ),
                              ],
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: primaryRed,
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFFE5394A),
                                    Color(0xFFC51F32),
                                  ],
                                ),
                              ),
                              // Same image as the app icon on the phone.
                              child: Center(
                                child: Image.asset(
                                  'assets/logo_drop.png',
                                  width: 90,
                                  height: 90,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 30),

                    // ==================================================
                    // APP NAME
                    // ==================================================
                    FadeTransition(
                      opacity: _textAnimation,
                      child: Column(
                        children: [
                          Text(
                            'BloodConnect',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.1,
                              color: titleColor,
                            ),
                          ),

                          const SizedBox(height: 9),

                          Text(
                            'Connecting donors. Saving lives.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.15,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 44),

                    // ==================================================
                    // PREMIUM LOADING
                    // ==================================================
                    AnimatedBuilder(
                      animation: _loadingController,
                      builder: (context, child) {
                        final value = _loadingController.value;

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (index) {
                            final delay = index * 0.18;

                            double animation = (value - delay) % 1.0;

                            animation = Curves.easeInOut.transform(animation);

                            final size = 5.0 + (animation * 3);

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                color: primaryRed.withValues(
                                  alpha: 0.35 + (animation * 0.65),
                                ),
                                shape: BoxShape.circle,
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ========================================================
          // BOTTOM BRAND MESSAGE
          // ========================================================
          Positioned(
            left: 24,
            right: 24,
            bottom: 38,
            child: FadeTransition(
              opacity: _textAnimation,
              child: Column(
                children: [
                  Text(
                    'Every drop can make a difference.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: subtitleColor,
                    ),
                  ),

                  const SizedBox(height: 7),

                  Text(
                    'BloodConnect',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: primaryRed.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BACKGROUND GLOW
  // ============================================================

  Widget _buildGlow({
    required double size,
    required Color color,
    required double opacity,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }
}
