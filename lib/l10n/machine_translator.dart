import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Translates the app's fixed texts. Only texts the app already knows
/// (menus, buttons, messages) are translated - users' own data such as
/// names or chat messages never is.
///
/// Two ways, chosen automatically:
///  1. On the phone with Google ML Kit (free, offline after a one-time
///     download of about 30 MB). Android / iOS only.
///  2. Online fallback (free MyMemory translation API) when ML Kit is not
///     available (Windows, Linux, Chrome, a missing plugin ...). Needs
///     internet; every translated text is saved on the phone, so it is
///     only fetched once.
class MachineTranslator extends ChangeNotifier {
  MachineTranslator._();

  static final MachineTranslator instance = MachineTranslator._();

  final OnDeviceTranslatorModelManager _models =
      OnDeviceTranslatorModelManager();

  final Map<String, Map<String, String>> _cache = {};
  final Queue<String> _queue = Queue<String>();
  final Set<String> _queued = {};

  OnDeviceTranslator? _translator;
  String? _readyCode;
  bool _online = false;
  bool _draining = false;
  Timer? _notifyTimer;
  DateTime? _blockedUntil;

  /// True when the current language is translated through the online API.
  bool get usingOnline => _online;

  static bool get _mlKitPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  TranslateLanguage? _languageFor(String code) {
    for (final language in TranslateLanguage.values) {
      if (language.bcpCode == code) return language;
    }
    return null;
  }

  /// Language code the online API expects.
  static String _apiCode(String code) => code == 'zh' ? 'zh-CN' : code;

  /// The reason the last prepare() failed (shown to help find the problem).
  String? lastError;

  /// Gets the language ready. Returns false if that did not work
  /// (no internet, unsupported phone ...).
  Future<bool> prepare(String code) async {
    lastError = null;

    if (!_mlKitPlatform) {
      return _prepareOnline(code);
    }

    final target = _languageFor(code);
    if (target == null) {
      lastError = 'This language is not supported by the translator.';
      return false;
    }

    OnDeviceTranslator? candidate;

    try {
      // The English model is normally built in. Try to fetch it, but do not
      // fail only because of it.
      try {
        if (!await _models.isModelDownloaded(TranslateLanguage.english.bcpCode)) {
          await _models.downloadModel(
            TranslateLanguage.english.bcpCode,
            isWifiRequired: false,
          );
        }
      } on MissingPluginException {
        rethrow;
      } catch (_) {}

      if (!await _models.isModelDownloaded(target.bcpCode)) {
        final ok = await _models.downloadModel(
          target.bcpCode,
          isWifiRequired: false,
        );
        if (!ok) {
          lastError =
              'The download did not finish. Check the internet and that Google Play services is on this phone.';
          // Try the online way before giving up.
          return _prepareOnline(code);
        }
      }

      candidate = OnDeviceTranslator(
        sourceLanguage: TranslateLanguage.english,
        targetLanguage: target,
      );

      // Real test: translate one word. If this works the language is ready.
      await candidate.translateText('Home');

      await _translator?.close();
      _translator = candidate;
      _online = false;
      _readyCode = code;
      _queue.clear();
      _queued.clear();

      notifyListeners();
      return true;
    } on MissingPluginException catch (e) {
      // ML Kit plugin is not in this build (hot restart after adding the
      // package, or an unsupported platform). Use the online way instead.
      debugPrint('ML Kit plugin missing, using online translation: $e');
      await candidate?.close();
      return _prepareOnline(code);
    } catch (e) {
      lastError = e.toString();
      debugPrint('Language download failed: $e');
      await candidate?.close();
      return _prepareOnline(code);
    }
  }

  // ------------------------------------------------------------
  // ONLINE WAY
  // ------------------------------------------------------------

  String _prefKey(String code) => 'online_translations_$code';

  Future<bool> _prepareOnline(String code) async {
    // Saved translations from earlier use (works without internet).
    var hasSaved = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey(code));
      if (saved != null) {
        final map = (jsonDecode(saved) as Map).cast<String, String>();
        (_cache[code] ??= {}).addAll(map);
        hasSaved = map.isNotEmpty;
      }
    } catch (_) {}

    if (!hasSaved) {
      // Check that the online service can be reached.
      try {
        final test = await _onlineTranslate('Home', code);
        if (test == null) throw Exception('Empty answer from translation service.');
      } catch (e) {
        lastError =
            'Online translation is not reachable. Check the internet. ($e)';
        return false;
      }
    }

    await _translator?.close();
    _translator = null;
    _online = true;
    _readyCode = code;
    _blockedUntil = null;
    _queue.clear();
    _queued.clear();
    lastError = null;

    notifyListeners();
    return true;
  }

  /// Returns the translation, null if the service gave no usable answer for
  /// this text, and throws if the service / internet is not available.
  Future<String?> _onlineTranslate(String text, String code) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': text,
      'langpair': 'en|${_apiCode(code)}',
      if (AppConfig.translateEmail.isNotEmpty) 'de': AppConfig.translateEmail,
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 429) {
      throw Exception('Daily free translation limit reached.');
    }
    if (response.statusCode != 200) {
      throw Exception('Translation service error ${response.statusCode}.');
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map) return null;

    final status = int.tryParse('${body['responseStatus']}');
    final data = body['responseData'];
    final out = data is Map ? data['translatedText'] : null;

    if (out is String && out.toUpperCase().contains('MYMEMORY WARNING')) {
      throw Exception('Daily free translation limit reached.');
    }
    if (status != 200 || out is! String || out.trim().isEmpty) return null;

    return out;
  }

  Future<void> _saveOnlineCache(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey(code), jsonEncode(_cache[code] ?? {}));
    } catch (_) {}
  }

  // ------------------------------------------------------------
  // LOOKUP
  // ------------------------------------------------------------

  /// The translation if we have it; otherwise the English text now,
  /// and the screen updates itself when the translation is ready.
  String lookup(String text, String code) {
    final hit = _cache[code]?[text];
    if (hit != null) return hit;

    final blocked =
        _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

    if (_readyCode == code && !blocked && _queued.add(text)) {
      _queue.add(text);
      _drain();
    }
    return text;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;

    try {
      while (_queue.isNotEmpty) {
        final code = _readyCode;
        if (code == null) break;

        if (_online) {
          await _drainOnlineBatch(code);
        } else {
          final translator = _translator;
          if (translator == null) break;

          final text = _queue.removeFirst();
          try {
            final result = await translator.translateText(text);
            (_cache[code] ??= {})[text] = result;
          } catch (_) {
            // Keep English for this text; do not retry it forever.
            (_cache[code] ??= {})[text] = text;
          }
        }
        _scheduleNotify();
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _drainOnlineBatch(String code) async {
    final batch = <String>[];
    while (_queue.isNotEmpty && batch.length < 4) {
      batch.add(_queue.removeFirst());
    }

    var failed = false;

    await Future.wait(batch.map((text) async {
      try {
        final result = await _onlineTranslate(text, code);
        // null = the service has no answer for this text: keep English.
        (_cache[code] ??= {})[text] = result ?? text;
      } catch (e) {
        failed = true;
        lastError = e.toString();
        _queued.remove(text); // may be tried again later
      }
    }));

    if (failed) {
      // Internet or daily limit problem: stop for 2 minutes, show English
      // for texts that are not translated yet.
      _blockedUntil = DateTime.now().add(const Duration(minutes: 2));
      for (final text in _queue) {
        _queued.remove(text);
      }
      _queue.clear();
    }

    if (_queue.isEmpty) {
      await _saveOnlineCache(code);
    }
  }

  void _scheduleNotify() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 150), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }
}
