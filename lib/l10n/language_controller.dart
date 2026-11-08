import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'machine_translator.dart';

class LanguageOption {
  const LanguageOption(this.name, this.code, this.native);

  /// English name (this is what is saved in users/{uid}.language).
  final String name;
  final String code;
  final String native;
}

/// Keeps the language chosen by the user.
/// English and Urdu are translated by hand. Every other language is
/// translated on the phone by Google ML Kit (see machine_translator.dart).
class LanguageController extends ChangeNotifier {
  LanguageController._();

  static final LanguageController instance = LanguageController._();

  static const List<LanguageOption> options = [
    LanguageOption('English', 'en', 'English'),
    LanguageOption('Urdu', 'ur', 'اردو'),
    LanguageOption('Arabic', 'ar', 'العربية'),
    LanguageOption('Chinese', 'zh', '中文'),
    LanguageOption('French', 'fr', 'Français'),
    LanguageOption('Spanish', 'es', 'Español'),
    LanguageOption('German', 'de', 'Deutsch'),
    LanguageOption('Turkish', 'tr', 'Türkçe'),
    LanguageOption('Hindi', 'hi', 'हिन्दी'),
    LanguageOption('Bengali', 'bn', 'বাংলা'),
    LanguageOption('Indonesian', 'id', 'Bahasa Indonesia'),
    LanguageOption('Russian', 'ru', 'Русский'),
  ];

  static LanguageOption? byName(String name) {
    for (final option in options) {
      if (option.name == name) return option;
    }
    return null;
  }

  static LanguageOption? byCode(String code) {
    for (final option in options) {
      if (option.code == code) return option;
    }
    return null;
  }

  static bool isMachine(String code) => code != 'en' && code != 'ur';

  static const String _prefKey = 'app_language_code';

  String _code = 'en';

  /// Call once in main() before runApp: loads the language saved on this
  /// phone so even the login / signup screens open in the chosen language.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      final option = saved == null ? null : byCode(saved);
      if (option != null) {
        _code = option.code;
        if (isMachine(_code)) {
          MachineTranslator.instance.prepare(_code); // never blocks start-up
        }
      }
    } catch (_) {
      // Keep English if storage is not available.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, _code);
    } catch (_) {}
  }

  String get code => _code;

  /// Locale given to Flutter's own widgets (dialogs, date pickers ...).
  /// Falls back to English when Flutter has no built-in texts for the language.
  Locale get materialLocale {
    final locale = Locale(_code);
    return _flutterSupports(locale) ? locale : const Locale('en');
  }

  static List<Locale> get supportedLocales => [
    for (final option in options)
      if (_flutterSupports(Locale(option.code))) Locale(option.code),
  ];

  static bool _flutterSupports(Locale locale) =>
      GlobalMaterialLocalizations.delegate.isSupported(locale) &&
      GlobalWidgetsLocalizations.delegate.isSupported(locale) &&
      GlobalCupertinoLocalizations.delegate.isSupported(locale);

  /// Choose a language. For machine-translated languages the model is
  /// downloaded first (needs internet). Returns false if that failed;
  /// the language then stays as it was.
  Future<bool> select(String name) async {
    final option = byName(name);
    if (option == null) return false;

    if (isMachine(option.code)) {
      final ready = await MachineTranslator.instance.prepare(option.code);
      if (!ready) return false;
    }

    _apply(option.code);
    return true;
  }

  /// Used at start-up / login with the saved value. Never blocks.
  void setByName(String? name) {
    final cleaned = (name ?? '').trim();
    // Account has no saved language: keep what the phone already uses.
    if (cleaned.isEmpty) return;

    final option = byName(cleaned);
    final newCode = option?.code ?? 'en';

    _apply(newCode);

    if (isMachine(newCode)) {
      MachineTranslator.instance.prepare(newCode);
    }
  }

  void _apply(String newCode) {
    if (newCode == _code) return;
    _code = newCode;
    _save();
    notifyListeners();
  }
}
