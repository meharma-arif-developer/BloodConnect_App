import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n/app_strings.dart';
import '../l10n/language_controller.dart';
import '../l10n/machine_translator.dart';
import '../l10n/app_text.dart';
import '../widgets/notification_preference_card.dart';
import 'chat_screen.dart';

import '../services/live_alerts.dart';
import '../services/push_service.dart';
import 'community/blood_camps_screen.dart';
import 'community/community_map_screen.dart';

import 'find_donor_screen.dart';
import 'request_blood_screen.dart';
import 'profile/profile_screen.dart';
import '../theme_controller.dart';

class ReceiverDashboardScreen extends StatefulWidget {
  final ThemeController themeController;

  const ReceiverDashboardScreen({super.key, required this.themeController});

  @override
  State<ReceiverDashboardScreen> createState() =>
      _ReceiverDashboardScreenState();
}

class _ReceiverDashboardScreenState extends State<ReceiverDashboardScreen> {
  int _currentIndex = 0;

  String _userName = 'Receiver';
  String _bloodGroup = 'Not set';
  String _city = 'Not set';
  bool _profileLoading = true;

  final List<String> _titles = [
    'Receiver Dashboard',
    'My Requests',
    'Alerts',
    'Community',
    'My Profile',
  ];

  @override
  void initState() {
    super.initState();
    _loadReceiverProfile();
    PushService.init();
    LiveAlerts.start(isDonor: false);
  }

  // ============================================================
  // LOAD PROFILE
  // ============================================================

  Future<void> _loadReceiverProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _profileLoading = false;
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (!doc.exists) {
        setState(() {
          _profileLoading = false;
        });
        return;
      }

      final data = doc.data() ?? {};

      setState(() {
        final name = data['name']?.toString().trim();

        _userName = name != null && name.isNotEmpty ? name : 'Receiver';

        _bloodGroup = data['bloodGroup']?.toString() ?? 'Not set';

        _city = data['city']?.toString() ?? 'Not set';

        _profileLoading = false;
      });
    } catch (e) {
      debugPrint('Receiver profile error: $e');

      if (!mounted) return;

      setState(() {
        _profileLoading = false;
      });
    }
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildRequestsTab(),
          _buildAlertsTab(),
          _buildCommunityTab(),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // ============================================================
  // APP BAR
  // ============================================================

  PreferredSizeWidget _buildAppBar() {
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titles[_currentIndex],
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _currentIndex == 0
                ? 'Your health, our connected community'
                : 'BloodConnect',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () {
            setState(() {
              _currentIndex = 2;
            });
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.notifications_none_rounded,
                color: theme.colorScheme.onSurface,
              ),
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE53935),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  // ============================================================
  // BOTTOM NAVIGATION
  // ============================================================

  Widget _buildBottomNavigationBar() {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        LanguageController.instance,
        MachineTranslator.instance,
      ]),
      builder: (context, _) {
        final langCode = LanguageController.instance.code;

        return NavigationBar(
      selectedIndex: _currentIndex,
      height: 70,
      elevation: 8,
      backgroundColor: theme.cardColor,
      indicatorColor: const Color(0xFFFFEBEE),
      onDestinationSelected: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: Color(0xFFE53935)),
          label: AppStrings.translate('Home', langCode),
        ),
        NavigationDestination(
          icon: Icon(Icons.bloodtype_outlined),
          selectedIcon: Icon(Icons.bloodtype_rounded, color: Color(0xFFE53935)),
          label: AppStrings.translate('Requests', langCode),
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_none_rounded),
          selectedIcon: Icon(
            Icons.notifications_rounded,
            color: Color(0xFFE53935),
          ),
          label: AppStrings.translate('Alerts', langCode),
        ),
        NavigationDestination(
          icon: Icon(Icons.groups_outlined),
          selectedIcon: Icon(Icons.groups_rounded, color: Color(0xFFE53935)),
          label: AppStrings.translate('Community', langCode),
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded, color: Color(0xFFE53935)),
          label: AppStrings.translate('Profile', langCode),
        ),
      ],
        );
      },
    );
  }

  // ============================================================
  // HOME
  // ============================================================

  Widget _buildHomeTab() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeCard(),

          const SizedBox(height: 22),

          const UpcomingCampsSection(),

          const SizedBox(height: 24),

          _sectionTitle('Quick Actions'),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.search_rounded,
                  title: 'Find Donor',
                  subtitle: 'Search compatible donors',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FindDonorScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.bloodtype_rounded,
                  title: 'Request Blood',
                  subtitle: 'Create a new request',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RequestBloodScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _sectionTitle('Your Blood Need'),

          const SizedBox(height: 12),

          _buildBloodNeedCard(),

          const SizedBox(height: 24),

          _sectionTitle('Recent Requests'),

          const SizedBox(height: 12),

          _buildRecentRequests(),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFECB3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.health_and_safety_rounded,
                  color: Color(0xFFF57C00),
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'For your safety, always verify medical '
                    'information with qualified healthcare '
                    'professionals and authorized blood banks.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // WELCOME CARD
  // ============================================================

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE53935), Color(0xFFC62828)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE53935).withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileLoading ? 'Welcome!' : 'Welcome, $_userName!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _profileLoading
                      ? 'Preparing your dashboard...'
                      : '$_bloodGroup • $_city',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Find the blood support you need.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BLOOD NEED CARD
  // ============================================================

  Widget _buildBloodNeedCard() {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RequestBloodScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.bloodtype_rounded,
                color: Color(0xFFE53935),
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Need Blood?',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Create a request and let compatible '
                    'donors know that you need help.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Color(0xFFE53935),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // RECENT REQUESTS
  // ============================================================

  Widget _buildRecentRequests() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _InfoCard(
        icon: Icons.lock_outline_rounded,
        title: 'Login required',
        message: 'Please login again to view your requests.',
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('blood_requests')
          .where('requesterId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFFE53935)),
            ),
          );
        }

        if (snapshot.hasError) {
          return _InfoCard(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load requests',
            message: 'Please try again later.',
          );
        }

        final documents = (snapshot.data?.docs ?? []).toList();

        _sortRequests(documents);

        if (documents.isEmpty) {
          return _InfoCard(
            icon: Icons.bloodtype_rounded,
            title: 'No requests yet',
            message: 'Your recent blood requests will appear here.',
          );
        }

        final recent = documents.take(2).toList();

        return Column(
          children: recent.map((doc) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RequestPreviewCard(document: doc),
            );
          }).toList(),
        );
      },
    );
  }

  // ============================================================
  // REQUESTS PAGE
  // ============================================================

  Widget _buildRequestsTab() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(child: Text('Please login again.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('blood_requests')
          .where('requesterId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFE53935)),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorState();
        }

        final documents = (snapshot.data?.docs ?? []).toList();

        _sortRequests(documents);

        return _RequestsContent(
          documents: documents,
          onCreateRequest: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RequestBloodScreen()),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // SORT REQUESTS
  // ============================================================

  void _sortRequests(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    documents.sort((a, b) {
      final aTimestamp = a.data()['createdAt'];
      final bTimestamp = b.data()['createdAt'];

      if (aTimestamp is Timestamp && bTimestamp is Timestamp) {
        return bTimestamp.compareTo(aTimestamp);
      }

      if (aTimestamp is Timestamp) return -1;
      if (bTimestamp is Timestamp) return 1;

      return 0;
    });
  }

  // ============================================================
  // ERROR STATE
  // ============================================================

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFFFEBEE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFFE53935),
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              'We could not load your blood requests.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {});
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ALERTS
  // ============================================================

  Widget _buildAlertsTab() {
    final user = FirebaseAuth.instance.currentUser;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        _buildPageHeader(
          icon: Icons.notifications_active_rounded,
          title: 'Alerts & Updates',
          subtitle: 'Live updates when donors respond to your blood requests.',
        ),
        const SizedBox(height: 20),
        if (user == null)
          const _InfoCard(
            icon: Icons.lock_outline_rounded,
            title: 'Login required',
            message: 'Please login again to see request updates.',
          )
        else
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('donor_requests')
                .where('requesterId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFE53935)),
                  ),
                );
              }
              if (snapshot.hasError) {
                return const _InfoCard(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load alerts',
                  message: 'Please check your internet connection and try again.',
                );
              }
              final docs = (snapshot.data?.docs ?? []).toList()
                ..sort((a, b) {
                  final aTime = a.data()['updatedAt'] ?? a.data()['createdAt'];
                  final bTime = b.data()['updatedAt'] ?? b.data()['createdAt'];
                  final aMs = aTime is Timestamp
                      ? aTime.millisecondsSinceEpoch
                      : 0;
                  final bMs = bTime is Timestamp
                      ? bTime.millisecondsSinceEpoch
                      : 0;
                  return bMs.compareTo(aMs);
                });
              if (docs.isEmpty) {
                return const _InfoCard(
                  icon: Icons.notifications_none_rounded,
                  title: 'No donor responses yet',
                  message: 'Responses to your blood requests will appear here.',
                );
              }
              return Column(
                children: docs.map((doc) {
                  final data = doc.data();
                  final status = (data['status'] ?? 'pending').toString();
                  final donor = (data['donorName'] ?? 'A donor').toString();
                  final group =
                      (data['bloodGroup'] ?? data['donorBloodGroup'] ?? '')
                          .toString();
                  final hospital =
                      (data['hospitalName'] ?? 'your requested location')
                          .toString();
                  final timeValue = data['updatedAt'] ?? data['createdAt'];
                  String timeLabel = 'Recently';
                  if (timeValue is Timestamp) {
                    final date = timeValue.toDate();
                    timeLabel = '${date.day}/${date.month}/${date.year}';
                  }
                  final accepted = status.toLowerCase() == 'accepted';
                  final completed = status.toLowerCase() == 'completed';
                  final rejected = status.toLowerCase() == 'rejected';
                  final donorPhone = (data['donorPhone'] ?? '').toString();
                  final contactSuffix = accepted && donorPhone.isNotEmpty
                      ? '\nDonor contact: $donorPhone'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AlertCard(
                      icon: accepted || completed
                          ? Icons.volunteer_activism_rounded
                          : rejected
                          ? Icons.close_rounded
                          : Icons.bloodtype_rounded,
                      title: accepted
                          ? 'Donor accepted your request'
                          : completed
                          ? 'Request marked completed'
                          : rejected
                          ? 'Donor declined the request'
                          : 'Donor request sent',
                      message: accepted
                          ? '$donor accepted your request for $group blood at $hospital. Please coordinate safely.$contactSuffix'
                          : completed
                          ? '$donor marked the blood request as completed.'
                          : rejected
                          ? '$donor is unable to help with this request.'
                          : 'Your donor request is waiting for a response.',
                      time: timeLabel,
                      type: 'Donor response',
                      isUnread: accepted,
                      onChat: (accepted || completed)
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  donorRequestId: doc.id,
                                  otherUserId: (data['donorId'] ?? '')
                                      .toString(),
                                  otherName: donor,
                                ),
                              ),
                            )
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        const SizedBox(height: 12),
        const _AlertCard(
          icon: Icons.health_and_safety_rounded,
          title: 'Safety Reminder',
          message: 'Always confirm blood compatibility and medical requirements with qualified healthcare professionals and authorized blood banks.',
          time: 'Reminder',
          type: 'Safety',
        ),
        const SizedBox(height: 24),
        const NotificationPreferenceCard(isDonor: false),
      ],
    );
  }

  // ============================================================
  // COMMUNITY
  // ============================================================

  Widget _buildCommunityTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        _buildPageHeader(
          icon: Icons.groups_rounded,
          title: 'BloodConnect Community',
          subtitle: 'Discover blood camps, healthcare facilities and useful blood-donation information.',
        ),

        const SizedBox(height: 20),

        _buildCommunityHero(),

        const SizedBox(height: 22),

        _sectionTitle('Explore'),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _CommunityActionCard(
                icon: Icons.event_rounded,
                title: 'Blood Camps',
                subtitle: 'Upcoming camps',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BloodCampsScreen()),
                  );
                },
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _CommunityActionCard(
                icon: Icons.map_rounded,
                title: 'Nearby',
                subtitle: 'Hospitals & labs',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CommunityMapScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        const UpcomingCampsSection(),

        const SizedBox(height: 22),

        _sectionTitle('Smart Nearby Map'),

        const SizedBox(height: 12),

        _buildMapPreviewCard(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunityMapScreen()),
            );
          },
        ),

        const SizedBox(height: 22),

        _sectionTitle('Community Information'),

        const SizedBox(height: 12),

        const _CommunityInfoCard(
          icon: Icons.favorite_rounded,
          title: 'Every Donation Matters',
          description: 'One blood donation can become an important part of someone’s treatment and recovery.',
        ),

        const SizedBox(height: 12),

        const _CommunityInfoCard(
          icon: Icons.verified_user_rounded,
          title: 'Choose Verified Facilities',
          description: 'Use authorized hospitals, blood banks and healthcare facilities for blood-related services.',
        ),

        const SizedBox(height: 12),

        const _CommunityInfoCard(
          icon: Icons.health_and_safety_rounded,
          title: 'Medical Guidance',
          description: 'Blood compatibility and transfusion decisions should always be confirmed by qualified medical professionals.',
        ),
      ],
    );
  }

  // ============================================================
  // COMMUNITY HERO
  // ============================================================

  Widget _buildCommunityHero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8E24AA), Color(0xFF6A1B9A)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.public_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected for a Cause',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Find blood resources and useful healthcare information in your community.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MAP PREVIEW
  // ============================================================

  Widget _buildMapPreviewCard({required VoidCallback onTap}) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFE8F5E9), Color(0xFFE3F2FD)],
                    ),
                  ),
                  child: CustomPaint(painter: _MapPatternPainter()),
                ),
              ),

              Center(
                child: Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFFE53935),
                        size: 32,
                      ),
                      const SizedBox(height: 7),

                      const Text(
                        'Smart Nearby Map',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        'Find nearby blood camps, hospitals and labs.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),

                      const SizedBox(height: 9),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Open Map',
                          style: TextStyle(
                            color: Color(0xFFE53935),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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
  // PROFILE
  // ============================================================

  Widget _buildProfileTab() {
    return ProfileScreen(themeController: widget.themeController);
  }

  // ============================================================
  // PAGE HEADER
  // ============================================================

  Widget _buildPageHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: const Color(0xFFE53935), size: 25),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  // ============================================================
  // STAGE B MESSAGE
  // ============================================================

  void _showStageBMessage(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF212121),
          content: Text(
            '$feature will be connected with real-time '
            'location and map data in Stage B.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

// =================================================================
// REQUESTS CONTENT
// =================================================================

class _RequestsContent extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> documents;

  final VoidCallback onCreateRequest;

  const _RequestsContent({
    required this.documents,
    required this.onCreateRequest,
  });

  @override
  State<_RequestsContent> createState() => _RequestsContentState();
}

class _RequestsContentState extends State<_RequestsContent> {
  String _selectedFilter = 'All';

  final List<String> _filters = ['All', 'Pending', 'Accepted', 'Completed'];

  @override
  Widget build(BuildContext context) {
    final filtered = widget.documents.where((document) {
      if (_selectedFilter == 'All') {
        return true;
      }

      final status = (document.data()['status'] ?? 'pending')
          .toString()
          .toLowerCase();

      return status == _selectedFilter.toLowerCase();
    }).toList();

    final pending = _countStatus('pending');

    final accepted = _countStatus('accepted');

    final completed = _countStatus('completed');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        _buildHeader(),

        const SizedBox(height: 20),

        _buildStatistics(pending, accepted, completed),

        const SizedBox(height: 22),

        _buildFilterBar(),

        const SizedBox(height: 18),

        if (filtered.isEmpty)
          _buildEmptyFilteredState()
        else
          ...filtered.map((document) => _RequestCard(document: document)),
      ],
    );
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------

  Widget _buildHeader() {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.bloodtype_rounded,
            color: Color(0xFFE53935),
            size: 27,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Track Your Requests',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Monitor the progress of every blood request from one place.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // STATISTICS
  // ------------------------------------------------------------

  Widget _buildStatistics(int pending, int accepted, int completed) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.access_time_rounded,
            value: pending.toString(),
            label: 'Pending',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.check_circle_outline_rounded,
            value: accepted.toString(),
            label: 'Accepted',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.task_alt_rounded,
            value: completed.toString(),
            label: 'Completed',
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // FILTER BAR
  // ------------------------------------------------------------

  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filters.map((filter) {
          final selected = _selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _selectedFilter = filter;
                });
              },
              selectedColor: const Color(0xFFE53935),
              backgroundColor: Theme.of(context).cardColor,
              side: BorderSide(
                color: selected
                    ? const Color(0xFFE53935)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.4),
              ),
              labelStyle: TextStyle(
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ------------------------------------------------------------
  // EMPTY FILTERED
  // ------------------------------------------------------------

  Widget _buildEmptyFilteredState() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_rounded, color: Color(0xFFE53935), size: 48),
          const SizedBox(height: 12),
          Text(
            _selectedFilter == 'All'
                ? 'No Blood Requests'
                : 'No $_selectedFilter Requests',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _selectedFilter == 'All'
                ? 'Create a blood request when you need help.'
                : 'There are no requests in this category.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface
                  .withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: widget.onCreateRequest,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Request Blood'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  int _countStatus(String status) {
    return widget.documents.where((doc) {
      final value = (doc.data()['status'] ?? 'pending')
          .toString()
          .toLowerCase();

      return value == status;
    }).length;
  }
}

// =================================================================
// STAT CARD
// =================================================================

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFFE53935), size: 21),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// REQUEST CARD
// =================================================================

class _RequestCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> document;

  const _RequestCard({required this.document});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = document.data();

    final patient = (data['patientName'] ?? 'Unknown Patient').toString();

    final bloodGroup = (data['bloodGroup'] ?? 'Not set').toString();

    final hospital = (data['hospitalName'] ?? 'Hospital not specified')
        .toString();

    final location = (data['location'] ?? 'Location not specified').toString();

    final country = (data['country'] ?? '').toString();

    final urgency = (data['urgency'] ?? 'Normal').toString();

    final status = (data['status'] ?? 'pending').toString();

    final units = (data['unitsRequired'] ?? 1).toString();

    final createdAt = data['createdAt'];

    DateTime? date;

    if (createdAt is Timestamp) {
      date = createdAt.toDate();
    }

    final urgent = urgency.toLowerCase() == 'urgent';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: urgent
              ? const Color(0xFFFFCDD2)
              : theme.dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    bloodGroup,
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      patient,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hospital,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              _StatusBadge(status: status),
            ],
          ),

          const SizedBox(height: 15),

          Divider(color: theme.dividerColor.withValues(alpha: 0.45)),

          const SizedBox(height: 12),

          _InfoRow(
            icon: Icons.location_on_rounded,
            label: 'Location',
            value: country.isEmpty ? location : '$location, $country',
          ),

          const SizedBox(height: 9),

          _InfoRow(
            icon: Icons.water_drop_rounded,
            label: 'Blood Needed',
            value: '$bloodGroup • $units unit${units == '1' ? '' : 's'}',
          ),

          const SizedBox(height: 9),

          _InfoRow(
            icon: urgent ? Icons.priority_high_rounded : Icons.schedule_rounded,
            label: 'Urgency',
            value: urgency,
            valueColor: urgent
                ? const Color(0xFFE53935)
                : Colors.orange.shade700,
          ),

          const SizedBox(height: 9),

          _InfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Created',
            value: date == null ? 'Date unavailable' : _formatDate(date),
          ),
          if (status.toLowerCase() == 'pending') ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _cancelRequest(context, document),
                icon: const Icon(Icons.cancel_outlined, size: 17),
                label: const Text('Cancel Request'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  side: const BorderSide(color: Color(0xFFE53935)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _cancelRequest(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final fresh = await transaction.get(document.reference);
        if (!fresh.exists) throw Exception('This request no longer exists.');
        final data = fresh.data() ?? <String, dynamic>{};
        if ((data['requesterId'] ?? '').toString() != user.uid) {
          throw Exception('You cannot cancel someone else’s request.');
        }
        if ((data['status'] ?? 'pending').toString().toLowerCase() !=
            'pending') {
          throw Exception('Only pending requests can be cancelled.');
        }
        transaction.update(document.reference, {
          'status': 'cancelled',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Blood request cancelled.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }
}

// =================================================================
// REQUEST PREVIEW
// =================================================================

class _RequestPreviewCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> document;

  const _RequestPreviewCard({required this.document});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = document.data();

    final bloodGroup = (data['bloodGroup'] ?? 'Not set').toString();

    final patient = (data['patientName'] ?? 'Unknown Patient').toString();

    final hospital = (data['hospitalName'] ?? 'Hospital').toString();

    final status = (data['status'] ?? 'pending').toString();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                bloodGroup,
                style: const TextStyle(
                  color: Color(0xFFE53935),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  patient,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hospital,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          _StatusBadge(status: status),
        ],
      ),
    );
  }
}

// =================================================================
// STATUS BADGE
// =================================================================

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase().trim();

    Color background;
    Color foreground;
    IconData icon;
    String label;

    switch (normalized) {
      case 'accepted':
        background = Colors.green.shade50;
        foreground = Colors.green.shade700;
        icon = Icons.check_circle_rounded;
        label = 'Accepted';
        break;

      case 'completed':
        background = Colors.blue.shade50;
        foreground = Colors.blue.shade700;
        icon = Icons.task_alt_rounded;
        label = 'Completed';
        break;

      case 'rejected':
        background = Colors.red.shade50;
        foreground = Colors.red.shade700;
        icon = Icons.close_rounded;
        label = 'Rejected';
        break;

      case 'cancelled':
      case 'canceled':
        background = Colors.grey.shade200;
        foreground = Colors.grey.shade700;
        icon = Icons.cancel_rounded;
        label = 'Cancelled';
        break;

      default:
        background = Colors.orange.shade50;
        foreground = Colors.orange.shade800;
        icon = Icons.access_time_rounded;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// INFO ROW
// =================================================================

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFFE53935)),
        const SizedBox(width: 9),
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// =================================================================
// ACTION CARD
// =================================================================

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFFE53935)),
            ),
            const SizedBox(height: 13),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =================================================================
// COMMUNITY ACTION CARD
// =================================================================

class _CommunityActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CommunityActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: const Color(0xFFE53935)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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

// =================================================================
// ALERT CARD
// =================================================================

class _AlertCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String time;
  final String type;
  final bool isUnread;
  final VoidCallback? onChat;

  const _AlertCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.time,
    required this.type,
    this.isUnread = false,
    this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUnread
              ? const Color(0xFFFFCDD2)
              : theme.dividerColor.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: const Color(0xFFE53935), size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (isUnread)
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        type,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFFE53935),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 9,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                if (onChat != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onChat,
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Chat with donor'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// COMMUNITY INFO CARD
// =================================================================

class _CommunityInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _CommunityInfoCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: const Color(0xFFE53935)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.45,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// INFO CARD
// =================================================================

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: const Color(0xFFE53935)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================
// MAP PATTERN PAINTER
// =================================================================

class _MapPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path1 = Path();

    path1.moveTo(0, size.height * 0.25);
    path1.cubicTo(
      size.width * 0.2,
      size.height * 0.05,
      size.width * 0.35,
      size.height * 0.45,
      size.width * 0.55,
      size.height * 0.2,
    );
    path1.cubicTo(
      size.width * 0.7,
      size.height * 0.02,
      size.width * 0.82,
      size.height * 0.45,
      size.width,
      size.height * 0.3,
    );

    canvas.drawPath(path1, paint);

    final path2 = Path();

    path2.moveTo(0, size.height * 0.75);
    path2.cubicTo(
      size.width * 0.2,
      size.height * 0.55,
      size.width * 0.4,
      size.height * 0.9,
      size.width * 0.6,
      size.height * 0.65,
    );
    path2.cubicTo(
      size.width * 0.78,
      size.height * 0.45,
      size.width * 0.9,
      size.height * 0.85,
      size.width,
      size.height * 0.7,
    );

    canvas.drawPath(path2, paint);

    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke;

    final road = Path();

    road.moveTo(size.width * 0.1, size.height);
    road.cubicTo(
      size.width * 0.25,
      size.height * 0.7,
      size.width * 0.35,
      size.height * 0.35,
      size.width * 0.8,
      0,
    );

    canvas.drawPath(road, roadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
