import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mixroom/helpers/instrument_picker_categories.dart';
import 'package:mixroom/l10n/l10n.dart';

void main() {
  test('guitars have a stable visible picker category', () {
    expect(normalizeInstrumentPickerCategory('guitar'), 'Guitars');
    expect(normalizeInstrumentPickerCategory('GUITARS'), 'Guitars');
    expect(
      instrumentPickerCategoryForValues(
        declaredCategory: 'instrument',
        instrumentId: 'sfz.guitar.steel_acoustic',
        instrumentName: 'Acoustic Guitar',
      ),
      'Guitars',
    );
    expect(
      instrumentPickerCategoryForValues(
        explicitPickerCategory: 'Guitars',
        instrumentId: 'sfz.guitar.clean_electric',
      ),
      'Guitars',
    );

    final keysIndex = kInstrumentPickerOrderedCategories.indexOf('Keys');
    final guitarsIndex = kInstrumentPickerOrderedCategories.indexOf('Guitars');
    expect(guitarsIndex, keysIndex + 1);
  });

  testWidgets('Guitars is translated in every supported locale', (
    tester,
  ) async {
    const expected = <String, String>{
      'en': 'Guitars',
      'ko': '기타 악기',
      'ja': 'ギター',
    };

    for (final entry in expected.entries) {
      late String translated;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(entry.key),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) {
              translated = L10n.translate(context, 'Guitars');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(translated, entry.value, reason: 'Locale ${entry.key}.');
    }
  });
}
