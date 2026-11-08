import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart' hide Text;
import '../l10n/app_strings.dart';
import '../l10n/app_text.dart';

import '../services/push_relay.dart';
import 'find_donor_screen.dart';

class RequestBloodScreen extends StatefulWidget {
  const RequestBloodScreen({super.key});

  @override
  State<RequestBloodScreen> createState() => _RequestBloodScreenState();
}

class _RequestBloodScreenState extends State<RequestBloodScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _patientNameController = TextEditingController();

  final TextEditingController _hospitalController = TextEditingController();

  final TextEditingController _cityController = TextEditingController();

  final TextEditingController _locationController = TextEditingController();

  final TextEditingController _unitsController = TextEditingController();

  final TextEditingController _phoneController = TextEditingController();

  final TextEditingController _descriptionController = TextEditingController();

  String? _selectedBloodGroup;
  String _urgency = 'Normal';
  bool _isSubmitting = false;

  DateTime? _requiredDate;

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

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  // ============================================================
  // LOAD USER PROFILE
  // ============================================================

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data() ?? {};

        final phone = (data['phone'] ?? '').toString();
        final city = (data['city'] ?? '').toString();
        final area = (data['area'] ?? '').toString();

        setState(() {
          if (phone.isNotEmpty) {
            _phoneController.text = phone;
          }

          if (city.isNotEmpty) {
            _cityController.text = city;
          }

          if (area.isNotEmpty) {
            _locationController.text = area;
          }
        });
      }
    } catch (e) {
      debugPrint('Profile loading error: $e');
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _patientNameController.dispose();
    _hospitalController.dispose();
    _cityController.dispose();
    _locationController.dispose();
    _unitsController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();

    super.dispose();
  }

  // ============================================================
  // SELECT REQUIRED DATE
  // ============================================================

  Future<void> _selectRequiredDate() async {
    final now = DateTime.now();

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _requiredDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      helpText: 'Select Required Date',
    );

    if (selectedDate == null) return;

    setState(() {
      _requiredDate = selectedDate;
    });
  }

  // ============================================================
  // SUBMIT BLOOD REQUEST
  // ============================================================

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedBloodGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a blood group.')),
      );
      return;
    }

    if (_requiredDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the required date.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your session has expired. Please login again.'),
        ),
      );
      return;
    }

    final units = int.tryParse(_unitsController.text.trim());

    if (units == null || units < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid blood units.')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Get latest user profile.
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};

      final requesterName = (userData['name'] ?? '').toString();

      final requesterPhone = _phoneController.text.trim();
      final requesterCountry = (userData['country'] ?? '').toString();
      final city = _cityController.text.trim();
      final area = _locationController.text.trim();

      // ========================================================
      // SAVE REQUEST
      // ========================================================

      final requestRef = await FirebaseFirestore.instance
          .collection('blood_requests')
          .add({
            // Request owner
            'requesterId': user.uid,
            'requesterName': requesterName,
            'requesterEmail': user.email ?? '',
            'requesterPhone': requesterPhone,

            // Patient information
            'patientName': _patientNameController.text.trim(),

            // Blood information
            'bloodGroup': _selectedBloodGroup,
            'unitsRequired': units,

            // Hospital information
            'hospitalName': _hospitalController.text.trim(),
            'country': requesterCountry,
            'city': city,
            'area': area,
            'location': _locationController.text.trim(),

            // Request information
            'urgency': _urgency,
            'requiredDate': Timestamp.fromDate(_requiredDate!),
            'description': _descriptionController.text.trim(),

            // Request status
            'status': 'pending',

            // Timestamps
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      debugPrint('Blood request created: ${requestRef.id}');

      // Free push to matching donors (does nothing if the relay is off).
      PushRelay.notify('request', requestRef.id);

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      _showSuccessDialog(requestRef.id);
    } on FirebaseException catch (e) {
      debugPrint('Firebase error: ${e.code} - ${e.message}');

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Unable to create blood request.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      debugPrint('Blood request error: $e');

      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ============================================================
  // SUCCESS DIALOG
  // ============================================================

  void _showSuccessDialog(String requestId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF2E7D32),
                  size: 42,
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'Request Created!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              const Text(
                'Your blood request has been submitted successfully. '
                'Now you can find matching donors.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.5, fontSize: 14),
              ),

              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FindDonorScreen(requestId: requestId),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Find Matching Donors',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
          'Request Blood',
          style: TextStyle(
            color: Color(0xFF171717),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        leading: IconButton(
          onPressed: _isSubmitting
              ? null
              : () {
                  Navigator.pop(context);
                },
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF171717)),
        ),
      ),

      body: Form(
        key: _formKey,

        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 35),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(),

              const SizedBox(height: 24),

              const Text(
                'Patient Information',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 14),

              _buildTextField(
                controller: _patientNameController,
                label: 'Patient Name',
                hint: 'Enter patient name',
                icon: Icons.person_outline_rounded,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppStrings.tr('Please enter patient name');
                  }

                  return null;
                },
              ),

              const SizedBox(height: 15),

              _buildBloodGroupDropdown(),

              const SizedBox(height: 15),

              _buildTextField(
                controller: _unitsController,
                label: 'Blood Units Required',
                hint: 'e.g. 2',
                icon: Icons.water_drop_outlined,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppStrings.tr('Please enter required units');
                  }

                  final units = int.tryParse(value.trim());

                  if (units == null || units < 1) {
                    return AppStrings.tr('Enter a valid number');
                  }

                  return null;
                },
              ),

              const SizedBox(height: 26),

              const Text(
                'Hospital Information',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 14),

              _buildTextField(
                controller: _hospitalController,
                label: 'Hospital Name',
                hint: 'Enter hospital name',
                icon: Icons.local_hospital_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppStrings.tr('Please enter hospital name');
                  }

                  return null;
                },
              ),

              const SizedBox(height: 15),

              _buildTextField(
                controller: _cityController,
                label: 'City',
                hint: 'e.g. Lahore',
                icon: Icons.location_city_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppStrings.tr('Please enter city');
                  }

                  return null;
                },
              ),

              const SizedBox(height: 15),

              _buildTextField(
                controller: _locationController,
                label: 'Area / Location',
                hint: 'e.g. Johar Town',
                icon: Icons.location_on_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppStrings.tr('Please enter location');
                  }

                  return null;
                },
              ),

              const SizedBox(height: 15),

              _buildTextField(
                controller: _phoneController,
                label: 'Contact Number',
                hint: 'e.g. +92 300 1234567',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppStrings.tr('Please enter contact number');
                  }

                  if (value.trim().length < 7) {
                    return AppStrings.tr('Enter a valid contact number');
                  }

                  return null;
                },
              ),

              const SizedBox(height: 26),

              const Text(
                'Request Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 14),

              _buildRequiredDateField(),

              const SizedBox(height: 15),

              _buildDescriptionField(),

              const SizedBox(height: 26),

              const Text(
                'Urgency Level',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 14),

              _buildUrgencySelector(),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 56,

                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitRequest,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE57373),
                    elevation: 0,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.send_rounded),
                            SizedBox(width: 10),
                            Text(
                              'Submit Blood Request',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
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
  // HEADER CARD
  // ============================================================

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),

      child: const Row(
        children: [
          Icon(Icons.favorite_rounded, color: Color(0xFFE53935), size: 35),

          SizedBox(width: 14),

          Expanded(
            child: Text(
              'Create a blood request and let nearby donors know that someone needs help.',
              style: TextStyle(
                color: Color(0xFF7F1D1D),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
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

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BLOOD GROUP DROPDOWN
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
            hintText: AppStrings.tr('Select blood group'),

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

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFE53935),
                width: 1.5,
              ),
            ),
          ),

          items: _bloodGroups.map((group) {
            return DropdownMenuItem<String>(value: group, child: Text(group));
          }).toList(),

          onChanged: _isSubmitting
              ? null
              : (value) {
                  setState(() {
                    _selectedBloodGroup = value;
                  });
                },
        ),
      ],
    );
  }

  // ============================================================
  // REQUIRED DATE
  // ============================================================

  Widget _buildRequiredDateField() {
    final dateText = _requiredDate == null
        ? 'Select required date'
        : '${_requiredDate!.day.toString().padLeft(2, '0')}/'
              '${_requiredDate!.month.toString().padLeft(2, '0')}/'
              '${_requiredDate!.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        const Text(
          'Required Date',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF444444),
          ),
        ),

        const SizedBox(height: 8),

        InkWell(
          onTap: _isSubmitting ? null : _selectRequiredDate,

          borderRadius: BorderRadius.circular(14),

          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),

            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),

            child: Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  color: Color(0xFFE53935),
                ),

                const SizedBox(width: 12),

                Text(
                  dateText,
                  style: TextStyle(
                    fontSize: 15,
                    color: _requiredDate == null
                        ? Colors.grey
                        : const Color(0xFF222222),
                  ),
                ),

                const Spacer(),

                const Icon(Icons.arrow_drop_down_rounded, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DESCRIPTION
  // ============================================================

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        const Text(
          'Description',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF444444),
          ),
        ),

        const SizedBox(height: 8),

        TextFormField(
          controller: _descriptionController,
          maxLines: 4,
          keyboardType: TextInputType.multiline,

          decoration: InputDecoration(
            hintText: AppStrings.tr('Add any important information about the request...'),

            alignLabelWithHint: true,

            prefixIcon: const Padding(
              padding: EdgeInsets.only(bottom: 65),
              child: Icon(Icons.notes_outlined, color: Color(0xFFE53935)),
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

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFE53935),
                width: 1.5,
              ),
            ),

            contentPadding: const EdgeInsets.all(15),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // URGENCY SELECTOR
  // ============================================================

  Widget _buildUrgencySelector() {
    return Row(
      children: [
        Expanded(
          child: _UrgencyButton(
            title: 'Normal',
            icon: Icons.schedule_rounded,
            selected: _urgency == 'Normal',
            color: const Color(0xFF2E7D32),

            onTap: () {
              setState(() {
                _urgency = 'Normal';
              });
            },
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: _UrgencyButton(
            title: 'Urgent',
            icon: Icons.warning_amber_rounded,
            selected: _urgency == 'Urgent',
            color: const Color(0xFFE53935),

            onTap: () {
              setState(() {
                _urgency = 'Urgent';
              });
            },
          ),
        ),
      ],
    );
  }
}

// ================================================================
// URGENCY BUTTON
// ================================================================

class _UrgencyButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _UrgencyButton({
    required this.title,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(14),

      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),

        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.08) : Colors.white,

          borderRadius: BorderRadius.circular(14),

          border: Border.all(
            color: selected ? color : const Color(0xFFEEEEEE),

            width: selected ? 1.5 : 1,
          ),
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Icon(icon, color: selected ? color : Colors.grey, size: 20),

            const SizedBox(width: 7),

            Text(
              title,
              style: TextStyle(
                color: selected ? color : Colors.grey,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
