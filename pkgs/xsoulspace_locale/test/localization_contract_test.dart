import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_locale/xsoulspace_locale.dart';

void main() {
  const english = UiLanguage('en', 'English');
  const russian = UiLanguage('ru', 'Russian');

  setUp(() {
    LocalizationConfig.initialize(
      LocalizationConfig(
        supportedLanguages: const <UiLanguage>[english, russian],
        fallbackLanguage: english,
      ),
    );
  });

  group('UiLanguage lookup', () {
    test('falls back to configured fallback language', () {
      final byCode = UiLanguage.byCodeWithFallback('de');

      expect(byCode, english);
      expect(Locales.fallback, const Locale('en'));
    });

    test('converts locale to language and back', () {
      final language = UiLanguage.byLocale(const Locale('ru'));

      expect(language, russian);
      expect(language.locale, const Locale('ru'));
    });
  });

  group('LocalizedMap helpers', () {
    test('supports json roundtrip and language fallback', () {
      final map = LocalizedMap.fromJson(<String, String>{
        'en': 'Hello',
        'ru': 'Privet',
      });

      expect(map.getValue(const Locale('ru')), 'Privet');
      expect(map.getValueByLanguage(const UiLanguage('de', 'German')), 'Hello');

      final json = map.toJson();
      expect(json['en'], 'Hello');
      expect(json['ru'], 'Privet');
    });

    test('locale string converters are deterministic', () {
      expect(localeFromString('en'), const Locale('en'));
      expect(localeToString(const Locale('ru')), 'ru');
      expect(localeFromString(''), isNull);
    });
  });

  group('LocaleLogic', () {
    test('throws for unsupported locale updates', () async {
      const logic = LocaleLogic();

      await expectLater(
        logic.updateLocale(
          newLocale: const Locale('de'),
          oldLocale: const Locale('en'),
          uiLocale: const Locale('en'),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
