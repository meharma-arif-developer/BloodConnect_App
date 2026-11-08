import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/app_text.dart';
import '../../services/camp_service.dart';
import '../../services/geocoder.dart';
import '../../services/safety_service.dart';

const Color _red = Color(0xFFE53935);

String formatCampDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
}

/// City and name saved in the signed-in user's profile ('' if unknown).
Future<Map<String, String>> _loadMyProfile() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return {};
  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = snap.data() ?? {};
    return {
      'city': CampService.cityOnly('${data['city'] ?? ''}'),
      'name': '${data['name'] ?? ''}',
    };
  } catch (_) {
    return {};
  }
}

void _toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red : null,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

// ================================================================
// FULL LIST OF CAMPS
// ================================================================

class BloodCampsScreen extends StatefulWidget {
  const BloodCampsScreen({super.key, this.initialCity});

  /// City to filter by when the screen opens (for example the city that
  /// was searched on the map).
  final String? initialCity;

  @override
  State<BloodCampsScreen> createState() => _BloodCampsScreenState();
}

class _BloodCampsScreenState extends State<BloodCampsScreen> {
  final TextEditingController _filter = TextEditingController();
  String _myCity = '';

  @override
  void initState() {
    super.initState();
    _filter.text = widget.initialCity ?? '';
    _loadMyProfile().then((p) {
      if (!mounted) return;
      setState(() => _myCity = p['city'] ?? '');
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _matches(BloodCamp camp) {
    final q = _filter.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return camp.city.toLowerCase().contains(q) ||
        camp.address.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Blood Camps',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _red,
        foregroundColor: Colors.white,
        onPressed: () => openAddCamp(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Post a camp'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _filter,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: AppStrings.tr('Filter by city'),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_myCity.isNotEmpty)
                      IconButton(
                        tooltip: 'My city',
                        icon: const Icon(Icons.home_rounded),
                        onPressed: () => setState(() => _filter.text = _myCity),
                      ),
                    if (_filter.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _filter.clear()),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<BloodCamp>>(
              stream: CampService.upcoming(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Camps could not be loaded. Please try again.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: _red),
                  );
                }

                final camps = snapshot.data!.where(_matches).toList();

                if (camps.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.event_busy_rounded,
                              size: 54, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(
                            _filter.text.trim().isEmpty
                                ? 'No upcoming blood camps yet.'
                                : 'No camps match this city.',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Be the first to post a camp or event so donors nearby can see it.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: camps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => CampCard(camp: camps[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openAddCamp(BuildContext context) async {
  final posted = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => const AddCampScreen()),
  );
  if (posted == true && context.mounted) {
    _toast(context, 'Camp posted.');
  }
}

// ================================================================
// ONE CAMP (full card)
// ================================================================

class CampCard extends StatelessWidget {
  const CampCard({super.key, required this.camp});

  final BloodCamp camp;

  Future<void> _call(BuildContext context) async {
    final cleaned = camp.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    try {
      if (!await launchUrl(uri) && context.mounted) {
        _toast(context, 'Unable to open phone dialer.', error: true);
      }
    } catch (_) {
      if (context.mounted) {
        _toast(context, 'Unable to open phone dialer.', error: true);
      }
    }
  }

  Future<void> _openMap(BuildContext context) async {
    final query = camp.latitude != null && camp.longitude != null
        ? '${camp.latitude},${camp.longitude}'
        : Uri.encodeComponent('${camp.address}, ${camp.city}');
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          context.mounted) {
        _toast(context, 'Unable to open the map.', error: true);
      }
    } catch (_) {
      if (context.mounted) {
        _toast(context, 'Unable to open the map.', error: true);
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this camp?'),
        content: const Text('This camp will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await CampService.delete(camp.id);
      if (context.mounted) _toast(context, 'Camp deleted.');
    } catch (_) {
      if (context.mounted) {
        _toast(context, 'Could not delete the camp.', error: true);
      }
    }
  }

  Future<void> _report(BuildContext context) async {
    try {
      await SafetyService.reportUser(
        reportedUserId: camp.createdBy,
        reason: 'Fake or misleading blood camp',
        description: 'Camp "${camp.title}" (${camp.id})',
      );
      if (context.mounted) _toast(context, 'Camp reported. Thank you.');
    } catch (_) {
      if (context.mounted) {
        _toast(context, 'Could not send the report.', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.65);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bloodtype_rounded, color: _red),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        camp.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${camp.organizerType.isEmpty ? '' : '${camp.organizerType} • '}${camp.organizer}',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(Icons.event_rounded, formatCampDate(camp.date), muted),
            if (camp.timeText.isNotEmpty)
              _row(Icons.schedule_rounded, camp.timeText, muted),
            _row(
              Icons.location_on_outlined,
              '${camp.address}, ${camp.city}',
              muted,
            ),
            if (camp.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(camp.description, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (camp.phone.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _call(context),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('Call'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _openMap(context),
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text('Map'),
                ),
                if (camp.isMine)
                  TextButton.icon(
                    onPressed: () => _delete(context),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 18, color: Colors.red),
                    label: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _report(context),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Report'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color))),
        ],
      ),
    );
  }
}

// ================================================================
// HOME / COMMUNITY STRIP: next camps
// ================================================================

/// Shows the next camps (camps in the user's city first). Used on the
/// Home and Community tabs of both dashboards.
class UpcomingCampsSection extends StatefulWidget {
  const UpcomingCampsSection({super.key});

  @override
  State<UpcomingCampsSection> createState() => _UpcomingCampsSectionState();
}

class _UpcomingCampsSectionState extends State<UpcomingCampsSection> {
  String _myCity = '';
  late final Stream<List<BloodCamp>> _stream = CampService.upcoming();

  @override
  void initState() {
    super.initState();
    _loadMyProfile().then((p) {
      if (!mounted) return;
      setState(() => _myCity = p['city'] ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Upcoming Blood Camps',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BloodCampsScreen()),
              ),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        StreamBuilder<List<BloodCamp>>(
          stream: _stream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text('Camps could not be loaded. Please try again.');
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _red,
                    ),
                  ),
                ),
              );
            }

            final all = snapshot.data!;
            final mine = all
                .where((c) => CampService.isNear(c, city: _myCity))
                .toList();
            final others = all.where((c) => !mine.contains(c)).toList();
            final shown = [...mine, ...others].take(3).toList();

            if (shown.isEmpty) {
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded, color: _red),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('No upcoming blood camps yet.'),
                      ),
                      TextButton(
                        onPressed: () => openAddCamp(context),
                        child: const Text('Post a camp'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                for (final camp in shown) ...[
                  _CampTile(camp: camp, inMyCity: mine.contains(camp)),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CampTile extends StatelessWidget {
  const _CampTile({required this.camp, required this.inMyCity});

  final BloodCamp camp;
  final bool inMyCity;

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                BloodCampsScreen(initialCity: CampService.cityOnly(camp.city)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${camp.date.day}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: _red,
                        height: 1,
                      ),
                    ),
                    Text(
                      formatCampDate(camp.date).split(' ')[2],
                      style: const TextStyle(fontSize: 10, color: _red),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      camp.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${camp.city}${camp.timeText.isEmpty ? '' : ' • ${camp.timeText}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              if (inMyCity)
                const Icon(Icons.near_me_rounded, size: 18, color: _red),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// POST A CAMP
// ================================================================

class AddCampScreen extends StatefulWidget {
  const AddCampScreen({super.key});

  @override
  State<AddCampScreen> createState() => _AddCampScreenState();
}

class _AddCampScreenState extends State<AddCampScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _organizer = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();

  String _type = CampService.organizerTypes.first;
  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadMyProfile().then((p) {
      if (!mounted) return;
      if (_city.text.isEmpty) _city.text = p['city'] ?? '';
      if (_organizer.text.isEmpty) _organizer.text = p['name'] ?? '';
      setState(() {});
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _organizer.dispose();
    _city.dispose();
    _address.dispose();
    _phone.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end) ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      _toast(context, 'Please choose the date.', error: true);
      return;
    }
    if (_start == null) {
      _toast(context, 'Please choose the start time.', error: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final city = _city.text.trim();
      final address = _address.text.trim();

      // Best effort: find the map position so the camp can be matched by
      // distance. If it fails the camp is still saved with its city name.
      var geo = await Geocoder.search('$address, $city');
      geo ??= await Geocoder.search(city);

      if (!mounted) return;

      final timeText = _end == null
          ? _start!.format(context)
          : '${_start!.format(context)} - ${_end!.format(context)}';

      await CampService.add(
        title: _title.text.trim(),
        organizer: _organizer.text.trim(),
        organizerType: _type,
        city: city,
        address: address,
        date: _date!,
        timeText: timeText,
        phone: _phone.text.trim(),
        description: _description.text.trim(),
        latitude: geo?.lat,
        longitude: geo?.lng,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Post camp error: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context, 'Could not post the camp. Please try again.', error: true);
    }
  }

  String? _required(String? v, int min, String message) =>
      (v == null || v.trim().length < min) ? AppStrings.tr(message) : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'New Blood Camp',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _title,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr('Camp / event title'),
                    counterText: '',
                  ),
                  validator: (v) => _required(v, 3, 'Please enter a title.'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _organizer,
                  maxLength: 80,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr('Organizer name'),
                    counterText: '',
                  ),
                  validator: (v) =>
                      _required(v, 2, 'Please enter the organizer name.'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr('Organizer type'),
                  ),
                  items: [
                    for (final t in CampService.organizerTypes)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? _type),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _city,
                  maxLength: 60,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr('City'),
                    counterText: '',
                  ),
                  validator: (v) => _required(v, 2, 'Please enter the city.'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  maxLength: 160,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr('Address / venue'),
                    counterText: '',
                  ),
                  validator: (v) =>
                      _required(v, 3, 'Please enter the address or venue.'),
                ),
                const SizedBox(height: 12),
                _pickerTile(
                  icon: Icons.event_rounded,
                  label: _date == null ? 'Choose date' : formatCampDate(_date!),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _pickerTile(
                        icon: Icons.schedule_rounded,
                        label: _start == null
                            ? 'Start time'
                            : _start!.format(context),
                        onTap: () => _pickTime(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _pickerTile(
                        icon: Icons.schedule_rounded,
                        label: _end == null ? 'End time' : _end!.format(context),
                        onTap: () => _pickTime(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  maxLength: 20,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr('Phone (optional)'),
                    counterText: '',
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    return RegExp(r'^[0-9+\-\s()]{6,20}$').hasMatch(t)
                        ? null
                        : AppStrings.tr('Please enter a valid phone number.');
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  maxLength: 300,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr('Description (optional)'),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _red),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Post Camp'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: _red, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
}
