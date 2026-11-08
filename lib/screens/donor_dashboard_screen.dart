import 'package:flutter/material.dart' hide Text;
import '../l10n/app_strings.dart';
import '../l10n/language_controller.dart';
import '../l10n/machine_translator.dart';
import '../l10n/app_text.dart';
import '../widgets/notification_preference_card.dart';
import 'chat_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/live_alerts.dart';
import '../services/push_relay.dart';
import '../services/push_service.dart';
import '../services/safety_service.dart';
import 'community/blood_camps_screen.dart';
import 'community/community_map_screen.dart';

import 'find_donor_screen.dart';
import 'profile/profile_screen.dart';
import '../theme_controller.dart';

class DonorDashboardScreen extends StatefulWidget {
  final ThemeController themeController;

  const DonorDashboardScreen({super.key, required this.themeController});

  @override
  State<DonorDashboardScreen> createState() => _DonorDashboardScreenState();
}

class _DonorDashboardScreenState extends State<DonorDashboardScreen> {
  int _currentIndex = 0;
  bool isAvailable = true;

  String _userName = 'Donor';
  String _bloodGroup = 'Not set';
  String _city = 'Not set';
  bool _profileLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDonorProfile();
    PushService.init();
    LiveAlerts.start(isDonor: true);
  }

  Future<void> _loadDonorProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) return;

      final data = doc.data() ?? {};

      if (!mounted) return;

      setState(() {
        _userName = data['name']?.toString().trim().isNotEmpty == true
            ? data['name'].toString()
            : 'Donor';

        _bloodGroup = data['bloodGroup']?.toString() ?? 'Not set';

        _city = data['city']?.toString() ?? 'Not set';

        isAvailable = data['donorAvailable'] ?? true;

        _profileLoading = false;
      });
    } catch (e) {
      debugPrint('Profile loading error: $e');

      if (mounted) {
        setState(() {
          _profileLoading = false;
        });
      }
    }
  }

  Future<void> _updateAvailability(bool value) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    setState(() {
      isAvailable = value;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      batch.set(firestore.collection('users').doc(user.uid), {
        'donorAvailable': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(firestore.collection('donor_profiles').doc(user.uid), {
        'donorAvailable': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (e) {
      debugPrint('Availability update error: $e');
    }
  }

  // ============================================================
  // OPEN COMMUNITY MAP
  // ============================================================

  void _openCommunityMap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CommunityMapScreen()),
    );
  }

  final List<String> _titles = [
    'Donor Dashboard',
    'Blood Requests',
    'Alerts',
    'Community',
    'My Profile',
  ];

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
              color: theme.colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _currentIndex == 0 ? 'Help save a life today' : 'BloodConnect',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              fontSize: 12,
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
          icon: Icon(
            Icons.notifications_none_rounded,
            color: theme.colorScheme.onSurface,
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
      backgroundColor: theme.cardColor,
      elevation: 8,
      height: 70,
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
  // HOME TAB
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

          const SizedBox(height: 22),

          Text(
            'Your Availability',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 10),

          _buildAvailabilityCard(),

          const SizedBox(height: 24),

          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.bloodtype_rounded,
                  title: 'Blood Requests',
                  subtitle: 'View requests',
                  onTap: () {
                    setState(() {
                      _currentIndex = 1;
                    });
                  },
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: _ActionCard(
                  icon: Icons.search_rounded,
                  title: 'Find Donors',
                  subtitle: 'Search donors',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FindDonorScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _buildDonationStatusCard(),

          const SizedBox(height: 24),

          Text(
            'Recent Blood Requests',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),

          const SizedBox(height: 12),

          const _RequestCard(
            bloodGroup: 'O+',
            hospital: 'City Hospital',
            location: 'Lahore',
            urgency: 'Urgent',
            time: '15 min ago',
          ),

          const SizedBox(height: 12),

          const _RequestCard(
            bloodGroup: 'A+',
            hospital: 'General Hospital',
            location: 'Islamabad',
            urgency: 'Today',
            time: '1 hour ago',
          ),

          const SizedBox(height: 12),

          const _RequestCard(
            bloodGroup: 'B-',
            hospital: 'Central Medical Center',
            location: 'Karachi',
            urgency: 'Tomorrow',
            time: '3 hours ago',
          ),

          const SizedBox(height: 24),

          _buildSafetyCard(),
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
          colors: [Color(0xFFE53935), Color(0xFFC62828)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
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

                const SizedBox(height: 5),

                Text(
                  _profileLoading
                      ? 'Loading your profile...'
                      : '$_bloodGroup • $_city\n'
                            'Your donation can help save someone’s life.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.4,
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
  // AVAILABILITY
  // ============================================================

  Widget _buildAvailabilityCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isAvailable
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isAvailable ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: isAvailable
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFFE53935),
              size: 26,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available for Donation',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  isAvailable
                      ? 'Nearby receivers can send you requests.'
                      : 'You will not receive new donor requests.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),

          Switch(
            value: isAvailable,
            activeTrackColor: const Color(0xFFE53935),
            onChanged: _updateAvailability,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DONATION STATUS
  // ============================================================

  Widget _buildDonationStatusCard() {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.volunteer_activism_rounded,
            color: Color(0xFFE53935),
            size: 30,
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to make a difference?',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  'Keep your availability updated so matching requests can reach you.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    height: 1.4,
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
  // REQUESTS TAB
  // ============================================================

  Widget _buildRequestsTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please log in to view donor requests.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('donor_requests')
          .where('donorId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load donor requests. Check Firestore rules.\\n${snapshot.error}',
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFE53935)),
          );
        }

        final docs = (snapshot.data?.docs ?? []).toList()
          ..sort((a, b) {
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];
            final aMillis = aTime is Timestamp
                ? aTime.millisecondsSinceEpoch
                : 0;
            final bMillis = bTime is Timestamp
                ? bTime.millisecondsSinceEpoch
                : 0;
            return bMillis.compareTo(aMillis);
          });

        final pending = docs
            .where(
              (d) =>
                  (d.data()['status'] ?? 'pending').toString().toLowerCase() ==
                  'pending',
            )
            .toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
          children: [
            _buildSectionIntro(
              icon: Icons.bloodtype_rounded,
              title: 'Incoming Blood Requests',
              subtitle:
                  'Review requests sent to you and respond when you can help.',
            ),
            const SizedBox(height: 20),
            if (docs.isEmpty)
              const _LiveRequestEmptyState(
                title: 'No requests yet',
                message:
                    'New requests sent to your donor profile will appear here.',
              )
            else
              ...docs.map((doc) {
                final data = doc.data();
                final status = (data['status'] ?? 'pending')
                    .toString()
                    .toLowerCase();
                final isPending = status == 'pending';
                final isAccepted = status == 'accepted';
                final isCompleted = status == 'completed';
                final bloodGroup = (data['bloodGroup'] ?? 'Not set').toString();
                final hospital =
                    (data['hospitalName'] ?? 'Hospital not provided')
                        .toString();
                final city = (data['city'] ?? '').toString();
                final urgency = (data['urgency'] ?? 'Normal').toString();
                final requester = (data['requesterName'] ?? 'Blood requester')
                    .toString();
                final units = (data['unitsRequired'] ?? 1).toString();
                final requesterPhone = (data['requesterPhone'] ?? '')
                    .toString();
                final contactSuffix = isAccepted && requesterPhone.isNotEmpty
                    ? '\nContact: $requesterPhone'
                    : '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LiveDonorRequestCard(
                    bloodGroup: bloodGroup,
                    title: hospital,
                    subtitle:
                        '$requester • ${city.isEmpty ? 'Location not set' : city}',
                    details: '$units unit(s) • $urgency$contactSuffix',
                    status: status,
                    onSafety: () => SafetyActions.showMenu(
                      context,
                      userId: (data['requesterId'] ?? '').toString(),
                      name: requester,
                    ),
                    onAccept: isPending
                        ? () => _respondToDonorRequest(doc.id, data, true)
                        : null,
                    onReject: isPending
                        ? () => _respondToDonorRequest(doc.id, data, false)
                        : null,
                    onComplete: isAccepted
                        ? () => _completeDonorRequest(doc.id, data)
                        : null,
                    onChat: (isAccepted || isCompleted)
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                donorRequestId: doc.id,
                                otherUserId: (data['requesterId'] ?? '')
                                    .toString(),
                                otherName: requester,
                              ),
                            ),
                          )
                        : null,
                  ),
                );
              }),
            const SizedBox(height: 12),
            _buildSafetyCard(),
          ],
        );
      },
    );
  }

  Widget _buildAlertsTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please log in to view alerts.'));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('donor_requests')
          .where('donorId', isEqualTo: user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Please check your internet connection and try again.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFE53935)),
          );
        }

        final docs = (snapshot.data?.docs ?? []).toList()
          ..sort((a, b) {
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];
            final aMillis = aTime is Timestamp
                ? aTime.millisecondsSinceEpoch
                : 0;
            final bMillis = bTime is Timestamp
                ? bTime.millisecondsSinceEpoch
                : 0;
            return bMillis.compareTo(aMillis);
          });

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
          children: [
            _buildSectionIntro(
              icon: Icons.notifications_rounded,
              title: 'Your Alerts',
              subtitle: 'Live updates about blood requests sent to your donor profile.',
            ),
            const SizedBox(height: 16),
            const NotificationPreferenceCard(isDonor: true),
            const SizedBox(height: 20),
            if (docs.isEmpty)
              const _LiveRequestEmptyState(
                title: 'You are all caught up',
                message: 'When a receiver sends you a donor request, it will appear here.',
              )
            else
              ...docs.map((doc) {
                final data = doc.data();
                final status = (data['status'] ?? 'pending')
                    .toString()
                    .toLowerCase();
                final group = (data['bloodGroup'] ?? 'Blood').toString();
                final hospital =
                    (data['hospitalName'] ?? 'Hospital not provided')
                        .toString();
                final city = (data['city'] ?? 'Location not set').toString();
                final requester = (data['requesterName'] ?? 'A receiver')
                    .toString();
                final isPending = status == 'pending';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _LiveAlertCard(
                    title: isPending
                        ? 'New donor request'
                        : 'Request ${_prettyStatus(status)}',
                    message:
                        '$requester needs $group blood at $hospital, $city.',
                    status: status,
                    onTap: () => setState(() => _currentIndex = 1),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _respondToDonorRequest(
    String donorRequestId,
    Map<String, dynamic> donorRequest,
    bool accept,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final donorRequestRef = FirebaseFirestore.instance
        .collection('donor_requests')
        .doc(donorRequestId);
    final bloodRequestId = (donorRequest['bloodRequestId'] ?? '').toString();
    if (bloodRequestId.isEmpty) {
      _showRequestMessage('This request is missing its blood request ID.');
      return;
    }
    final bloodRequestRef = FirebaseFirestore.instance
        .collection('blood_requests')
        .doc(bloodRequestId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final donorSnapshot = await transaction.get(donorRequestRef);
        final bloodSnapshot = await transaction.get(bloodRequestRef);
        // Own phone number, shared with the requester only when accepting.
        final ownUserSnapshot = accept
            ? await transaction.get(
                FirebaseFirestore.instance.collection('users').doc(user.uid),
              )
            : null;

        if (!donorSnapshot.exists) {
          throw Exception('The blood request is no longer available.');
        }
        final donorData = donorSnapshot.data() ?? <String, dynamic>{};

        if ((donorData['donorId'] ?? '').toString() != user.uid) {
          throw Exception('You are not authorized to respond to this request.');
        }
        if ((donorData['status'] ?? 'pending').toString().toLowerCase() !=
            'pending') {
          throw Exception('This donor request has already been handled.');
        }

        if (accept) {
          // Accepting assigns this donor to the blood request. Because this
          // runs inside a transaction, two donors can never both win.
          if (!bloodSnapshot.exists) {
            throw Exception('The blood request is no longer available.');
          }
          final bloodData = bloodSnapshot.data() ?? <String, dynamic>{};
          if ((bloodData['status'] ?? 'pending').toString().toLowerCase() !=
              'pending') {
            throw Exception(
              'This blood request is no longer open. Another donor may have accepted it.',
            );
          }

          transaction.update(donorRequestRef, {
            'status': 'accepted',
            'donorPhone': (ownUserSnapshot?.data()?['phone'] ?? '').toString(),
            'requesterPhone': (bloodData['requesterPhone'] ?? '').toString(),
            'responseAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          transaction.update(bloodRequestRef, {
            'status': 'accepted',
            'acceptedDonorId': user.uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Declining only changes this donor's own invitation.
          transaction.update(donorRequestRef, {
            'status': 'rejected',
            'responseAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });

      PushRelay.notify('response', donorRequestId);

      _showRequestMessage(accept ? 'Request accepted.' : 'Request declined.');
    } on FirebaseException catch (e) {
      debugPrint('Donor response error: ${e.code} - ${e.message}');
      _showRequestMessage(
        e.code == 'permission-denied'
            ? 'Permission denied. Check Firestore security rules.'
            : 'Could not update this request. Please try again.',
      );
    } catch (e) {
      _showRequestMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _completeDonorRequest(
    String donorRequestId,
    Map<String, dynamic> donorRequest,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final bloodRequestId = (donorRequest['bloodRequestId'] ?? '').toString();
    if (bloodRequestId.isEmpty) return;

    try {
      final donorRef = FirebaseFirestore.instance
          .collection('donor_requests')
          .doc(donorRequestId);
      final bloodRef = FirebaseFirestore.instance
          .collection('blood_requests')
          .doc(bloodRequestId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final donorSnap = await transaction.get(donorRef);
        final bloodSnap = await transaction.get(bloodRef);
        if (!donorSnap.exists || !bloodSnap.exists) {
          throw Exception('Request not found.');
        }
        if ((donorSnap.data()?['donorId'] ?? '').toString() != user.uid) {
          throw Exception('You are not authorized to complete this request.');
        }
        if ((donorSnap.data()?['status'] ?? '').toString().toLowerCase() !=
            'accepted') {
          throw Exception('Only an accepted request can be completed.');
        }
        final bloodData = bloodSnap.data() ?? <String, dynamic>{};
        if ((bloodData['status'] ?? '').toString().toLowerCase() !=
                'accepted' ||
            (bloodData['acceptedDonorId'] ?? '').toString() != user.uid) {
          throw Exception('This blood request is not assigned to you.');
        }
        transaction.update(donorRef, {
          'status': 'completed',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(bloodRef, {
          'status': 'completed',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      PushRelay.notify('response', donorRequestId);

      _showRequestMessage('Request marked as completed.');
    } catch (e) {
      _showRequestMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _prettyStatus(String status) {
    if (status.isEmpty) return 'updated';
    return status[0].toUpperCase() + status.substring(1);
  }

  // ============================================================
  // COMMUNITY TAB
  // ============================================================

  Widget _buildCommunityTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 30),
      children: [
        _buildSectionIntro(
          icon: Icons.groups_rounded,
          title: 'BloodConnect Community',
          subtitle: 'Learn, stay informed and help build a responsible donor community.',
        ),

        const SizedBox(height: 20),

        // ========================================================
        // SMART NEARBY MAP
        // ========================================================
        InkWell(
          onTap: _openCommunityMap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFFC62828)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.map_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),

                const SizedBox(width: 16),

                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Smart Nearby Map',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      SizedBox(height: 5),

                      Text(
                        'Find nearby blood camps, hospitals and laboratories.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // ========================================================
        // MAP ACTIONS
        // ========================================================
        Row(
          children: [
            Expanded(
              child: _CommunityMapActionCard(
                icon: Icons.bloodtype_rounded,
                title: 'Blood Camps',
                subtitle: 'Upcoming camps',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BloodCampsScreen()),
                ),
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _CommunityMapActionCard(
                icon: Icons.local_hospital_rounded,
                title: 'Nearby',
                subtitle: 'Hospitals & labs',
                onTap: _openCommunityMap,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        const UpcomingCampsSection(),

        const SizedBox(height: 20),

        const _CommunityCard(
          icon: Icons.favorite_rounded,
          title: 'Why Blood Donation Matters',
          description: 'Regular voluntary blood donation can help hospitals maintain blood supplies for patients who need transfusions.',
        ),

        const SizedBox(height: 12),

        const _CommunityCard(
          icon: Icons.health_and_safety_rounded,
          title: 'Donate Responsibly',
          description: 'Only donate when you are medically eligible and follow guidance from qualified healthcare professionals.',
        ),

        const SizedBox(height: 12),

        const _CommunityCard(
          icon: Icons.verified_user_rounded,
          title: 'Stay Safe',
          description: 'Use verified information, protect personal details and report suspicious activity through BloodConnect.',
        ),

        const SizedBox(height: 12),

        const _CommunityCard(
          icon: Icons.public_rounded,
          title: 'A Global Community',
          description: 'BloodConnect is designed to support users across different countries, regions and cities.',
        ),
      ],
    );
  }

  // ============================================================
  // PROFILE TAB
  // ============================================================

  Widget _buildProfileTab() {
    return ProfileScreen(themeController: widget.themeController);
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Widget _buildSectionIntro({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFFE53935)),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSafetyCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFFECB3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFF57C00), size: 24),

          SizedBox(width: 12),

          Expanded(
            child: Text(
              'BloodConnect helps connect donors and receivers. Only donate when medically eligible and follow advice from qualified healthcare professionals.',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRequestMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

// ================================================================
// LIVE REQUEST / ALERT WIDGETS
// ================================================================

class _LiveRequestEmptyState extends StatelessWidget {
  final String title;
  final String message;
  const _LiveRequestEmptyState({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 42, color: Color(0xFFE53935)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _LiveDonorRequestCard extends StatelessWidget {
  final String bloodGroup;
  final String title;
  final String subtitle;
  final String details;
  final String status;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onComplete;
  final VoidCallback? onSafety;
  final VoidCallback? onChat;

  const _LiveDonorRequestCard({
    required this.bloodGroup,
    required this.title,
    required this.subtitle,
    required this.details,
    required this.status,
    required this.onAccept,
    required this.onReject,
    required this.onComplete,
    this.onSafety,
    this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = status == 'pending';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    bloodGroup,
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w800,
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
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: .65,
                        ),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: .65,
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              label: Text(_statusLabel(status)),
              visualDensity: VisualDensity.compact,
              backgroundColor: status == 'accepted'
                  ? Colors.green.shade50
                  : status == 'pending'
                  ? Colors.orange.shade50
                  : Colors.grey.shade200,
            ),
          ),
          if (pending) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
          if (status == 'accepted' && onComplete != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Mark Completed'),
              ),
            ),
          ],
          if (onChat != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('Chat with receiver'),
              ),
            ),
          if (onSafety != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onSafety,
                child: const Text('Report or block requester'),
              ),
            ),
        ],
      ),
    );
  }

  static String _statusLabel(String value) =>
      value.isEmpty ? 'Unknown' : value[0].toUpperCase() + value.substring(1);
}

class _LiveAlertCard extends StatelessWidget {
  final String title;
  final String message;
  final String status;
  final VoidCallback onTap;
  const _LiveAlertCard({
    required this.title,
    required this.message,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pending = status == 'pending';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: .4),
          ),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFFFEBEE),
              child: Icon(Icons.bloodtype_rounded, color: Color(0xFFE53935)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: .7),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _statusLabel(status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: pending
                          ? Colors.orange.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(String value) =>
      value.isEmpty ? 'Unknown' : value[0].toUpperCase() + value.substring(1);
}

// ================================================================
// ACTION CARD
// ================================================================

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
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
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

            const SizedBox(height: 14),

            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// COMMUNITY MAP ACTION CARD
// ================================================================

class _CommunityMapActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CommunityMapActionCard({
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
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    subtitle,
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

            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// REQUEST CARD
// ================================================================

class _RequestCard extends StatelessWidget {
  final String bloodGroup;
  final String hospital;
  final String location;
  final String urgency;
  final String time;

  const _RequestCard({
    required this.bloodGroup,
    required this.hospital,
    required this.location,
    required this.urgency,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isUrgent = urgency == 'Urgent';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: Text(
                bloodGroup,
                style: const TextStyle(
                  color: Color(0xFFE53935),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hospital,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  '$location • $time',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isUrgent
                  ? const Color(0xFFFFEBEE)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              urgency,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isUrgent ? const Color(0xFFE53935) : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// REQUEST ACTION CARD
// ================================================================

class _RequestActionCard extends StatelessWidget {
  final String bloodGroup;
  final String hospital;
  final String location;
  final String urgency;
  final String time;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RequestActionCard({
    required this.bloodGroup,
    required this.hospital,
    required this.location,
    required this.urgency,
    required this.time,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    bloodGroup,
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hospital,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      '$location • $time',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: urgency == 'Urgent'
                      ? const Color(0xFFFFEBEE)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  urgency,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: urgency == 'Urgent'
                        ? const Color(0xFFE53935)
                        : Colors.black54,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                  ),
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ================================================================
// NOTIFICATION CARD
// ================================================================

class _NotificationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String time;
  final bool isImportant;

  const _NotificationCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.time,
    this.isImportant = false,
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
          color: isImportant
              ? const Color(0xFFFFCDD2)
              : theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
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
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
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

// ================================================================
// COMMUNITY CARD
// ================================================================

class _CommunityCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _CommunityCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFFE53935)),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    height: 1.5,
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
