import 'package:xsoulspace_locale/xsoulspace_locale.dart';

/// {@template support_localization}
/// Localization keys and default values for the support system.
///
/// Provides localized strings for email templates, labels, and messages
/// used throughout the support functionality.
/// {@endtemplate}
class SupportLocalization {
  SupportLocalization._();

  /// Email template keys
  static const helloSupportTeam = 'hello_support_team';
  static const experiencingIssue = 'experiencing_issue';
  static const issueDescription = 'issue_description';
  static const appInformation = 'app_information';
  static const deviceInformation = 'device_information';
  static const contactEmail = 'contact_email';
  static const userName = 'user_name';
  static const additionalContext = 'additional_context';
  static const additionalDetails = 'additional_details';
  static const provideAdditionalContext = 'provide_additional_context';
  static const sentFromApp = 'sent_from_app';

  /// Default values
  static const appFeedback = 'app_feedback';
  static const userFeedbackOrBugReport = 'user_feedback_or_bug_report';
  static const notProvided = 'not_provided';
  static const unknown = 'unknown';

  /// Labels
  static const version = 'version';
  static const build = 'build';
  static const package = 'package';
  static const appName = 'app_name';
  static const platform = 'platform';
  static const model = 'model';
  static const osVersion = 'os_version';
  static const manufacturer = 'manufacturer';

  /// Supported languages
  static const _en = UiLanguage('en', 'English');
  static const _ru = UiLanguage('ru', 'Russian');

  /// List of supported languages
  static const List<UiLanguage> supportedLanguages = [_en, _ru];

  /// Default language (English)
  static const UiLanguage defaultLanguage = _en;

  /// Default localization map with English and Russian translations
  static Map<String, LocalizedMap> get defaultLocalization => {
    helloSupportTeam: LocalizedMap(value: {_en: 'Hello,', _ru: 'Добрый день,'}),
    experiencingIssue: LocalizedMap(
      value: {
        _en: "I'm experiencing an issue with the app.",
        _ru: 'У меня возникла проблема с приложением.',
      },
    ),
    issueDescription: LocalizedMap(
      value: {_en: '**Issue Description:**', _ru: '**Описание проблемы:**'},
    ),
    appInformation: LocalizedMap(
      value: {_en: '**App Information:**', _ru: '**Информация о приложении:**'},
    ),
    deviceInformation: LocalizedMap(
      value: {
        _en: '**Device Information:**',
        _ru: '**Информация об устройстве:**',
      },
    ),
    contactEmail: LocalizedMap(
      value: {_en: '**Contact Email:**', _ru: '**Email для связи:**'},
    ),
    userName: LocalizedMap(
      value: {_en: '**User Name:**', _ru: '**Имя пользователя:**'},
    ),
    additionalContext: LocalizedMap(
      value: {
        _en: '**Additional Context:**',
        _ru: '**Дополнительный контекст:**',
      },
    ),
    additionalDetails: LocalizedMap(
      value: {
        _en: '**Additional Details:**',
        _ru: '**Дополнительные детали:**',
      },
    ),
    provideAdditionalContext: LocalizedMap(
      value: {
        _en: 'Please provide any additional context about your issue below:',
        _ru:
            'Пожалуйста, предоставьте дополнительную информацию о вашей проблеме ниже:',
      },
    ),
    sentFromApp: LocalizedMap(
      value: {
        _en: 'Sent from {appName} app',
        _ru: 'Отправлено из приложения {appName}',
      },
    ),
    appFeedback: LocalizedMap(
      value: {_en: 'App Feedback', _ru: 'Отзыв о приложении'},
    ),
    userFeedbackOrBugReport: LocalizedMap(
      value: {
        _en: 'User feedback or bug report',
        _ru: 'Отзыв пользователя или сообщение об ошибке',
      },
    ),
    notProvided: LocalizedMap(value: {_en: 'Not provided', _ru: 'Не указано'}),
    unknown: LocalizedMap(value: {_en: 'Unknown', _ru: 'Неизвестно'}),
    version: LocalizedMap(value: {_en: 'Version', _ru: 'Версия'}),
    build: LocalizedMap(value: {_en: 'Build', _ru: 'Сборка'}),
    package: LocalizedMap(value: {_en: 'Package', _ru: 'Пакет'}),
    appName: LocalizedMap(value: {_en: 'App Name', _ru: 'Название приложения'}),
    platform: LocalizedMap(value: {_en: 'Platform', _ru: 'Платформа'}),
    model: LocalizedMap(value: {_en: 'Model', _ru: 'Модель'}),
    osVersion: LocalizedMap(value: {_en: 'OS Version', _ru: 'Версия ОС'}),
    manufacturer: LocalizedMap(
      value: {_en: 'Manufacturer', _ru: 'Производитель'},
    ),
  };

  /// Gets a localized string for the specified key and language
  ///
  /// Returns the localized string for the given key and language.
  /// If the language is not available, falls back to the default language.
  /// If the key is not found, returns the fallback string.
  static String getLocalizedString(
    final String key,
    final UiLanguage language,
    final String fallback,
  ) {
    final localization = defaultLocalization[key];
    if (localization == null) {
      return fallback;
    }

    final localizedValue = localization.value[language];
    if (localizedValue != null) {
      return localizedValue;
    }

    // Fallback to default language
    final defaultValue = localization.value[defaultLanguage];
    if (defaultValue != null) {
      return defaultValue;
    }

    return fallback;
  }

  /// Gets a localized string from a custom LocalizedMap
  ///
  /// This method is used when a custom LocalizedMap is provided in the config.
  /// It first tries to get the string from the custom localization,
  /// then falls back to the default localization.
  static String getLocalizedStringFromMap(
    final LocalizedMap? customLocalization,
    final String key,
    final UiLanguage language,
    final String fallback,
  ) {
    // Try custom localization first
    if (customLocalization != null) {
      final customValue = customLocalization.value[language];
      if (customValue != null) {
        return customValue;
      }

      // Fallback to default language in custom localization
      final customDefaultValue = customLocalization.value[defaultLanguage];
      if (customDefaultValue != null) {
        return customDefaultValue;
      }
    }

    // Fallback to default localization
    return getLocalizedString(key, language, fallback);
  }

  /// Checks if a language is supported
  static bool isLanguageSupported(final UiLanguage language) =>
      supportedLanguages.contains(language);

  /// Gets all supported languages
  static List<UiLanguage> getSupportedLanguages() => supportedLanguages;
}
