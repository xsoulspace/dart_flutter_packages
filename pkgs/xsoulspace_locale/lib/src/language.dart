// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'localization.dart';

/// Utility class for accessing supported locales and fallback locale.
///
/// Provides static access to configured locale information.
///
/// @ai Use [values] to get all supported locales, [fallback] for default locale.
class Locales {
  Locales._();

  /// All supported Flutter locales.
  static List<Locale> get values =>
      LocalizationConfig.instance.supportedLocales;

  /// Default locale when system locale is not supported.
  static Locale get fallback =>
      LocalizationConfig.instance.fallbackLanguage.locale;

  /// Converts a [UiLanguage] to its corresponding [Locale].
  ///
  /// @ai Use this to convert between language and locale representations.
  static Locale byLanguage(final UiLanguage language) => Locale(language.code);
}

/// Keyboard language representation for input methods.
///
/// Provides type-safe keyboard language codes with caching.
///
/// ```dart
/// final keyboardLang = KeyboardLanguage.of('en');
/// ```
///
/// @ai Use for keyboard input configuration. Instances are cached by code.
class KeyboardLanguage extends Equatable {
  const KeyboardLanguage._(this.code);

  /// Creates keyboard language from UiLanguage.
  factory KeyboardLanguage.fromLanguage(final UiLanguage? language) =>
      language != null
      ? KeyboardLanguage.of(language.code)
      : KeyboardLanguage.defaultKeyboardLanguage();

  /// Creates or retrieves cached keyboard language by code.
  factory KeyboardLanguage.of(final String code) =>
      _values.putIfAbsent(code, () => KeyboardLanguage._(code));

  /// Default keyboard language from fallback configuration.
  factory KeyboardLanguage.defaultKeyboardLanguage() =>
      KeyboardLanguage.fromLanguage(
        LocalizationConfig.instance.fallbackLanguage,
      );

  /// The language code (e.g., 'en', 'es').
  final String code;

  static final Map<String, KeyboardLanguage> _values = {};

  /// All supported keyboard languages.
  static List<KeyboardLanguage> get values => LocalizationConfig
      .instance
      .supportedLanguages
      .map(KeyboardLanguage.fromLanguage)
      .toList();

  @override
  List<Object?> get props => [code];

  @override
  String toString() => 'KeyboardLanguage($code)';
}

/// Extracts language code from language string.
///
/// @ai Handles format like 'en_US' -> 'en'.
String getLanguageCodeByStr(final String language) => language.split('_').first;

/// Maps supported languages to their named locale representations.
///
/// @ai Use for language selection UI components.
Map<UiLanguage, NamedLocale> get namedLocalesMap => Map.fromEntries(
  LocalizationConfig.instance.supportedLanguages.map(
    (final lang) => MapEntry(
      lang,
      NamedLocale(name: lang.name, locale: Locales.byLanguage(lang)),
    ),
  ),
);

/// Represents a supported language with code and display name.
///
/// Core language entity used throughout the package.
///
/// ```dart
/// final english = UiLanguage('en', 'English');
/// final locale = english.locale; // Locale('en')
/// ```
///
/// @ai Use for language identification and conversion. Provides methods to
/// find languages by code with fallback support.
class UiLanguage extends Equatable {
  const UiLanguage(this.code, this.name);

  /// Language code (e.g., 'en', 'es').
  final String code;

  /// Display name (e.g., 'English', 'Spanish').
  final String name;

  /// All supported languages from configuration.
  static List<UiLanguage> get all =>
      LocalizationConfig.instance.supportedLanguages;

  /// Finds language by code, returns null if not found.
  static UiLanguage? byCode(final String languageCode) => LocalizationConfig
      .instance
      .supportedLanguages
      .firstWhereOrNull((final lang) => lang.code == languageCode);

  /// Finds language by code with fallback to default.
  ///
  /// @ai Use this when you need a guaranteed valid language.
  static UiLanguage byCodeWithFallback(final String languageCode) =>
      byCode(languageCode) ?? LocalizationConfig.instance.fallbackLanguage;

  /// Converts Flutter locale to UiLanguage with fallback.
  ///
  /// @ai Use this to convert from Flutter's Locale to package's UiLanguage.
  static UiLanguage byLocale(final Locale locale) =>
      byCodeWithFallback(locale.languageCode);

  /// Converts this language to Flutter locale.
  Locale get locale => Locales.byLanguage(this);

  @override
  List<Object?> get props => [code];
}

/// Extension to convert Flutter locales to UiLanguage.
///
/// @ai Provides convenient access to language information from Flutter locales.
extension UiLanguageX on Locale {
  /// Converts this locale to its corresponding UiLanguage.
  UiLanguage get language => UiLanguage.byLocale(this);
}
