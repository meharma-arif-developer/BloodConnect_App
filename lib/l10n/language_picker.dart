import 'package:flutter/material.dart' hide Text;

import '../services/app_messenger.dart';
import 'app_text.dart';
import 'language_controller.dart';
import 'machine_translator.dart';

/// Opens the language list (same dialog everywhere: login, signup,
/// onboarding and Profile). Downloads the language if needed and applies it.
/// [onChanged] is called with the English name (e.g. "Urdu") after the
/// language was really switched, so the caller can save it to the account.
Future<void> showLanguagePicker(
  BuildContext context, {
  Future<void> Function(String name)? onChanged,
}) async {
  final currentCode = LanguageController.instance.code;

  final chosen = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Select Language'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final option in LanguageController.options)
                RadioListTile<String>(
                  value: option.name,
                  groupValue: LanguageController.byCode(currentCode)?.name,
                  title: Text(option.native),
                  subtitle: option.native == option.name
                      ? null
                      : Text(option.name),
                  activeColor: Colors.red,
                  onChanged: (value) => Navigator.pop(dialogContext, value),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'English and Urdu are translated by hand. Other languages are translated by your phone and need a one-time download (about 30 MB).',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (chosen == null || !context.mounted) return;

  final option = LanguageController.byName(chosen);
  if (option == null || option.code == currentCode) return;

  final needsDownload = LanguageController.isMachine(option.code);

  if (needsDownload) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Color(0xFFE53935)),
            SizedBox(width: 16),
            Expanded(child: Text('Downloading language... please wait.')),
          ],
        ),
      ),
    );
  }

  final ok = await LanguageController.instance.select(chosen);

  if (needsDownload && context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  if (!ok) {
    final reason = MachineTranslator.instance.lastError;
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(
        backgroundColor: Colors.red,
        content: _msg(
          'Could not download this language. Check your internet and try again.'
          '${reason == null ? '' : '\n$reason'}',
        ),
      ),
    );
    return;
  }

  if (onChanged != null) {
    await onChanged(chosen);
  }
}

// SnackBar content is built outside the dialog; reuse the translating Text.
Widget _msg(String s) => Text(s);

/// Small globe button for the top of login / signup / onboarding screens.
class LanguageButton extends StatelessWidget {
  const LanguageButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: 'Language',
      icon: Icon(
        Icons.language_rounded,
        color: color ?? (isDark ? Colors.white : const Color(0xFF222222)),
      ),
      onPressed: () => showLanguagePicker(context),
    );
  }
}
