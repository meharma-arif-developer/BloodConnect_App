/// Feature switches. Everything here is safe for the FREE Firebase plan
/// by default. Only change a value after reading SETUP_AND_CHANGES.md.
class AppConfig {
  AppConfig._();

  /// Email code (OTP) after password login.
  /// Needs the Firebase Blaze plan + Cloud Functions + an email service key.
  static const bool emailOtpEnabled = false;

  /// Real push notifications through Firebase Cloud Functions.
  /// Needs the Firebase Blaze plan. Leave false if you use the free relay below.
  static const bool pushEnabled = false;

  /// FREE push notifications: address of your Cloudflare Worker, e.g.
  /// 'https://bloodconnect-push-relay.YOURNAME.workers.dev'
  /// (see push_relay/README.md). Empty = off.
  static const String pushRelayUrl = '';

  /// True when either push method is configured.
  static bool get pushActive => pushEnabled || pushRelayUrl.isNotEmpty;

  /// Support email shown in Profile > Contact Support.
  /// Put your real support email here. Leave empty to show no email.
  static const String supportEmail = '';

  /// Web address of the admin panel (opened from the "Admin Login" link).
  static const String adminPanelUrl = 'https://bloodconnect-life.web.app';

  /// Optional. Your email, sent to the free MyMemory translation service
  /// (used only when on-phone translation is not available, e.g. on
  /// Windows / Chrome). With an email the free daily limit is about 50,000
  /// characters instead of 5,000. Leave empty to stay anonymous.
  static const String translateEmail = '';

  /// Expanded blood-group matching. Keep false until a medical professional
  /// has approved the table in blood_compatibility.dart.
  static const bool expandedBloodCompatibility = false;
}
