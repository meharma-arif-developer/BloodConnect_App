import 'app_config.dart';

/// Which donor blood groups may be shown for a requested blood group.
///
/// SAFE DEFAULT: exact match only.
/// To allow other groups, a doctor / blood bank must approve the table below,
/// then set AppConfig.expandedBloodCompatibility = true.
class BloodCompatibility {
  BloodCompatibility._();

  /// requested group -> donor groups that may be offered.
  /// Currently every group lists only itself (no medical assumptions).
  static const Map<String, List<String>> approvedDonorGroups = {
    'A+': ['A+'],
    'A-': ['A-'],
    'B+': ['B+'],
    'B-': ['B-'],
    'AB+': ['AB+'],
    'AB-': ['AB-'],
    'O+': ['O+'],
    'O-': ['O-'],
  };

  /// PROPOSAL ONLY - NOT USED BY THE APP.
  /// This is the commonly published red-blood-cell chart (recipient -> donor
  /// groups). It is NOT approved for use. A doctor / blood bank must review it
  /// (blood product type, patient condition, local rules) before it is copied
  /// into `approvedDonorGroups` and AppConfig.expandedBloodCompatibility is
  /// set to true.
  static const Map<String, List<String>> proposedRedCellDonorGroups = {
    'O-': ['O-'],
    'O+': ['O+', 'O-'],
    'A-': ['A-', 'O-'],
    'A+': ['A+', 'A-', 'O+', 'O-'],
    'B-': ['B-', 'O-'],
    'B+': ['B+', 'B-', 'O+', 'O-'],
    'AB-': ['AB-', 'A-', 'B-', 'O-'],
    'AB+': ['AB+', 'AB-', 'A+', 'A-', 'B+', 'B-', 'O+', 'O-'],
  };

  static List<String> donorGroupsFor(String requested) {
    final group = requested.trim();
    if (!AppConfig.expandedBloodCompatibility) return [group];
    return approvedDonorGroups[group] ?? [group];
  }
}
