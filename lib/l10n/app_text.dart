import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as m show Text;

import 'app_strings.dart';
import 'language_controller.dart';
import 'machine_translator.dart';

/// Rebuilds every Text when the language changes or a translation arrives.
final Listenable _languageChanges = Listenable.merge([
  LanguageController.instance,
  MachineTranslator.instance,
]);

/// Drop-in replacement for Flutter's Text that shows the Urdu version of a
/// fixed text when the app language is Urdu. Everything else (style, maxLines,
/// const constructor ...) works exactly like Flutter's Text.
///
/// Use it by importing this file and hiding Flutter's Text:
///   import 'package:flutter/material.dart' hide Text;
///   import '../l10n/app_text.dart';
class Text extends StatelessWidget {
  const Text(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _languageChanges,
      builder: (context, _) {
        return m.Text(
          AppStrings.translate(data, LanguageController.instance.code),
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
          textDirection: textDirection,
          locale: locale,
          softWrap: softWrap,
          overflow: overflow,
          textScaler: textScaler,
          maxLines: maxLines,
          semanticsLabel: semanticsLabel,
          textWidthBasis: textWidthBasis,
          textHeightBehavior: textHeightBehavior,
          selectionColor: selectionColor,
        );
      },
    );
  }
}
