// providers/locale_provider.dart
import 'package:flutter/material.dart';
import 'package:mixroom/l10n/locale_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider with ChangeNotifier {
  static const String _localePrefKey = 'language_code';

  Locale? _locale;
  Future<void>? _loadFuture;

  Locale? get locale => _locale;

  Future<void> loadLocale() async {
    final existingLoad = _loadFuture;
    if (existingLoad != null) {
      return existingLoad;
    }

    final future = _loadLocaleInternal();
    _loadFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadFuture, future)) {
        _loadFuture = null;
      }
    }
  }

  Future<void> _loadLocaleInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final storedLanguageCode = prefs.getString(_localePrefKey);

    if (_locale != null) {
      final current = LocaleConfig.resolveLocale(_locale);
      if (storedLanguageCode != current.languageCode) {
        await prefs.setString(_localePrefKey, current.languageCode);
      }
      return;
    }

    Locale resolvedLocale;
    if (storedLanguageCode != null) {
      resolvedLocale = LocaleConfig.resolveLanguageCode(storedLanguageCode);
    } else {
      final deviceLocales = WidgetsBinding.instance.platformDispatcher.locales;
      resolvedLocale = LocaleConfig.fallbackLocale;
      for (final deviceLocale in deviceLocales) {
        if (LocaleConfig.isSupportedLanguageCode(deviceLocale.languageCode)) {
          resolvedLocale = LocaleConfig.resolveLocale(deviceLocale);
          break;
        }
      }
    }

    if (_locale != null) {
      return;
    }

    _locale = resolvedLocale;
    if (storedLanguageCode != resolvedLocale.languageCode) {
      await prefs.setString(_localePrefKey, resolvedLocale.languageCode);
    }

    notifyListeners();
  }

  Future<void> setLocale(Locale newLocale) async {
    final resolvedLocale = LocaleConfig.resolveLocale(newLocale);
    if (_locale == resolvedLocale) return;

    _locale = resolvedLocale;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localePrefKey, resolvedLocale.languageCode);
  }
}
