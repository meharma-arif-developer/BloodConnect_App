import 'package:flutter/material.dart';

class ThemeController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  // ============================================================
  // SET THEME
  // ============================================================

  void setTheme(String appearance) {
    switch (appearance) {
      case 'Dark':
        _themeMode = ThemeMode.dark;
        break;

      case 'Light':
        _themeMode = ThemeMode.light;
        break;

      case 'System':
      case 'System Default':
      default:
        _themeMode = ThemeMode.system;
        break;
    }

    notifyListeners();
  }
}
