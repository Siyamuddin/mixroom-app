import 'package:flutter/material.dart';

class LocaleConfig {
  static const Locale fallbackLocale = Locale('en');

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
    Locale('ja'),
  ];

  static const Map<String, String> languageNames = <String, String>{
    'en': 'English',
    'ko': '한국어',
    'ja': '日本語',
  };

  static const Map<String, String> languageFlags = <String, String>{
    'en': '🇺🇸',
    'ko': '🇰🇷',
    'ja': '🇯🇵',
  };

  static Locale resolveLocale(Locale? locale) {
    if (locale == null) return fallbackLocale;
    return resolveLanguageCode(locale.languageCode);
  }

  static bool isSupportedLanguageCode(String? languageCode) {
    if (languageCode == null) return false;
    final code = languageCode.toLowerCase();
    for (final locale in supportedLocales) {
      if (locale.languageCode == code) {
        return true;
      }
    }
    return false;
  }

  static Locale resolveLanguageCode(String? languageCode) {
    if (languageCode == null) return fallbackLocale;
    final code = languageCode.toLowerCase();
    for (final locale in supportedLocales) {
      if (locale.languageCode == code) {
        return locale;
      }
    }
    return fallbackLocale;
  }
}
