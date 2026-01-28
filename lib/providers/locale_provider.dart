// providers/locale_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider with ChangeNotifier {
  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('language_code');
    if (languageCode != null) {
      _locale = Locale(languageCode); // Only language code
      notifyListeners();
    } else {
      final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
      _locale = Locale(deviceLocale.languageCode); // Only language code
      notifyListeners();
      await prefs.setString('language_code', _locale!.languageCode);
    }
  }

  Future<void> setLocale(Locale newLocale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', newLocale.languageCode); // Only save language code
    _locale = newLocale;
    notifyListeners();
  }
}
