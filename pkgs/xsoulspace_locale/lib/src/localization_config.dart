import 'package:flutter/material.dart';

import 'localization.dart';

/// {@template localization_config}
/// Configuration singleton for locale support and fallback settings.
///
/// Must be initialized before using any locale functionality.
/// Defines supported languages and fallback behavior.
///
/// ```dart
/// const languages = (
///   en: UiLanguage('en', 'English'),
///   es: UiLanguage('es', 'Spanish'),
/// );
/// const supportedLanguages = [
///   languages.en,
///   languages.es,
/// ];
///
/// const localeLogic = LocaleLogic();
///
/// final uiLocaleResource = await localeLogic.createUiLocaleResource();
///
/// LocalizationConfig.initialize(LocalizationConfig(
///   supportedLanguages: supportedLanguages,
///   fallbackLanguage: uiLocaleResource.value.language,
/// ));
///
/// localeLogic.initUiLocaleResource(uiLocaleResource: uiLocaleResource);
///
/// ```
///
/// @ai Initialize this first in your app. Use [isLocaleSupported] and
/// [isLanguageSupported] to validate locale changes.
/// {@endtemplate}
class LocalizationConfig {
  /// {@macro localization_config}
  LocalizationConfig({
    required this.supportedLanguages,
    required this.fallbackLanguage,
  }) : supportedLocales = supportedLanguages
           .map((final lang) => lang.locale)
           .toList();

  /// List of supported languages for the application.
  final List<UiLanguage> supportedLanguages;

  /// Flutter locales derived from supported languages.
  final List<Locale> supportedLocales;

  /// Default language when system locale is not supported.
  final UiLanguage fallbackLanguage;

  static LocalizationConfig? _instance;

  /// Initializes the global configuration instance.
  ///
  /// @ai Call this once during app startup before any locale operations.
  // ignore: use_setters_to_change_properties
  static void initialize(final LocalizationConfig config) {
    _instance = config;
  }

  /// Gets the global configuration instance.
  ///
  /// @ai Throws if not initialized. Always check initialization before use.
  static LocalizationConfig get instance {
    if (_instance == null) {
      throw StateError('LocalizationConfig has not been initialized');
    }
    return _instance!;
  }

  /// Validates if a Flutter locale is supported.
  ///
  /// @ai Checks both exact match and language code match for flexibility.
  bool isLocaleSupported(final Locale locale) =>
      supportedLocales.contains(locale) ||
      supportedLocales.any(
        (final supportedLocale) =>
            supportedLocale.languageCode == locale.languageCode,
      );

  /// Validates if a UiLanguage is supported.
  ///
  /// @ai Checks both exact match and language code match for flexibility.
  bool isLanguageSupported(final UiLanguage language) =>
      supportedLanguages.contains(language) ||
      supportedLanguages.any(
        (final supportedLanguage) => supportedLanguage.code == language.code,
      );
}
