// providers/locale_provider.dart
import 'package:flutter/material.dart';
import 'package:mixroom/l10n/locale_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider with ChangeNotifier {
  static const String _localePrefKey = 'language_code';

  Locale? _locale;

  Locale? get locale => _locale;

  Future<void> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final storedLanguageCode = prefs.getString(_localePrefKey);

    if (storedLanguageCode != null) {
      _locale = LocaleConfig.resolveLanguageCode(storedLanguageCode);
    } else {
      final deviceLocales = WidgetsBinding.instance.platformDispatcher.locales;
      Locale resolvedLocale = LocaleConfig.fallbackLocale;
      for (final deviceLocale in deviceLocales) {
        if (LocaleConfig.isSupportedLanguageCode(deviceLocale.languageCode)) {
          resolvedLocale = LocaleConfig.resolveLocale(deviceLocale);
          break;
        }
      }
      _locale = resolvedLocale;
      await prefs.setString(_localePrefKey, _locale!.languageCode);
    }

    if (_locale != null && storedLanguageCode != _locale!.languageCode) {
      await prefs.setString(_localePrefKey, _locale!.languageCode);
    }

    notifyListeners();
  }

  Future<void> setLocale(Locale newLocale) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedLocale = LocaleConfig.resolveLocale(newLocale);
    await prefs.setString(_localePrefKey, resolvedLocale.languageCode);
    _locale = resolvedLocale;
    notifyListeners();
  }
}
