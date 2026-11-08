import 'package:flutter/material.dart' hide Text;
import '../l10n/app_text.dart';
import '../l10n/language_picker.dart';

import '../theme_controller.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final ThemeController themeController;

  const OnboardingScreen({super.key, required this.themeController});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  int _currentPage = 0;

  final List<OnboardingData> _pages = const [
    OnboardingData(
      icon: Icons.volunteer_activism_rounded,
      title: 'Give Blood',
      description:
          'Your one donation can become someone’s second chance at life.',
    ),
    OnboardingData(
      icon: Icons.search_rounded,
      title: 'Find a Donor',
      description: 'Find suitable blood donors quickly when you or your loved ones need help.',
    ),
    OnboardingData(
      icon: Icons.favorite_rounded,
      title: 'Save a Life',
      description:
          'Connect people who need blood with people who are ready to help.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    } else {
      _getStarted();
    }
  }

  void _skip() {
    _getStarted();
  }

  void _getStarted() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LoginScreen(themeController: widget.themeController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF101010)
          : const Color(0xFFFDF8F8),

      body: SafeArea(
        child: Column(
          children: [
            // =========================
            // TOP BAR
            // =========================

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),

              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [
                  const Text(
                    'BloodConnect',

                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFD62839),
                    ),
                  ),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const LanguageButton(),
                      TextButton(
                    onPressed: _skip,

                    style: TextButton.styleFrom(
                      foregroundColor: isDark
                          ? Colors.white70
                          : const Color(0xFF777777),
                    ),

                    child: const Text(
                      'Skip',

                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                    ],
                  ),
                ],
              ),
            ),

            // =========================
            // ONBOARDING PAGES
            // =========================
            Expanded(
              child: PageView.builder(
                controller: _pageController,

                itemCount: _pages.length,

                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },

                itemBuilder: (context, index) {
                  final page = _pages[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),

                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,

                      children: [
                        // =========================
                        // ILLUSTRATION
                        // =========================

                        Container(
                          width: size.width * 0.65,
                          height: size.width * 0.65,

                          constraints: const BoxConstraints(
                            maxWidth: 280,
                            maxHeight: 280,
                          ),

                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF3A171A)
                                : const Color(0xFFFFE8EA),

                            shape: BoxShape.circle,

                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFD62839)
                                    .withValues(alpha: 0.10),

                                blurRadius: 35,
                                spreadRadius: 5,
                              ),
                            ],
                          ),

                          child: Stack(
                            alignment: Alignment.center,

                            children: [
                              Container(
                                width: 190,
                                height: 190,

                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.white,

                                  shape: BoxShape.circle,

                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),

                                      blurRadius: 20,

                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                              ),

                              Icon(
                                page.icon,
                                size: 95,
                                color: const Color(0xFFD62839),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 48),

                        // =========================
                        // TITLE
                        // =========================
                        Text(
                          page.title,

                          textAlign: TextAlign.center,

                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,

                            color: isDark
                                ? Colors.white
                                : const Color(0xFF222222),

                            letterSpacing: -0.6,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // =========================
                        // DESCRIPTION
                        // =========================
                        Text(
                          page.description,

                          textAlign: TextAlign.center,

                          style: TextStyle(
                            fontSize: 16,
                            height: 1.55,
                            fontWeight: FontWeight.w400,

                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF777777),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // =========================
            // BOTTOM CONTROLS
            // =========================
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 10, 28, 28),

              child: Column(
                children: [
                  // =========================
                  // PAGE INDICATORS
                  // =========================

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,

                    children: List.generate(
                      _pages.length,

                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),

                        margin: const EdgeInsets.symmetric(horizontal: 4),

                        width: _currentPage == index ? 26 : 8,

                        height: 8,

                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? const Color(0xFFD62839)
                              : isDark
                              ? const Color(0xFF5A2529)
                              : const Color(0xFFFFC7CC),

                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // =========================
                  // NEXT / GET STARTED
                  // =========================
                  SizedBox(
                    width: double.infinity,
                    height: 56,

                    child: ElevatedButton(
                      onPressed: _nextPage,

                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD62839),

                        foregroundColor: Colors.white,

                        elevation: 0,

                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),

                      child: Text(
                        _currentPage == _pages.length - 1
                            ? 'Get Started'
                            : 'Next',

                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingData {
  final IconData icon;
  final String title;
  final String description;

  const OnboardingData({
    required this.icon,
    required this.title,
    required this.description,
  });
}
