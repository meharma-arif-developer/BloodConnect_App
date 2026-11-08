/// Shared legal text used by Signup and Profile.
/// IMPORTANT: this is a plain-language DRAFT. Have a qualified professional
/// review it before the app is released publicly.
class LegalTexts {
  LegalTexts._();

  static const String medicalDisclaimer =
      'BloodConnect only helps connect blood donors and people who need blood. '
      'It does not provide medical advice and does not replace doctors, blood '
      'banks or emergency medical services. In an emergency, contact your local '
      'emergency number or the nearest hospital.';

  static const String privacyPolicy =
      'What we collect: your name, email, phone number, city, country, blood '
      'group, availability, your requests and responses, and (if you allow '
      'notifications) a device token for sending alerts.\n\n'
      'Who can see it: signed-in users can see a donor\'s name, blood group, '
      'city and availability. Your phone number is private. It is shared only '
      'with the other person in a request after the donor accepts it.\n\n'
      'Location: used on your device to show nearby hospitals and labs. It is '
      'not stored in your profile.\n\n'
      'Your controls: you can edit your profile, switch availability on or off, '
      'report or block users, and delete your account. Deleting your account '
      'removes your profile and donor profile.\n\n'
      'This text is a draft and must be reviewed by a qualified professional '
      'before public release.';

  static const String terms =
      'BloodConnect helps connect donors and people requesting blood.\n\n'
      'You must provide accurate information and must not misuse the app, '
      'harass others, spam, or ask for money.\n\n'
      'Accounts that are reported for abuse may be suspended.\n\n'
      '$medicalDisclaimer\n\n'
      'Blood donation and medical decisions must always follow guidance from '
      'qualified healthcare professionals.\n\n'
      'This text is a draft and must be reviewed by a qualified professional '
      'before public release.';
}
