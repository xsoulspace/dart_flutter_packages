// ignore_for_file: avoid_print, lines_longer_than_80_chars

import 'package:xsoulspace_locale/xsoulspace_locale.dart';
import 'package:xsoulspace_support/xsoulspace_support.dart';

/// Example demonstrating how to use the localized support system
/// with xsoulspace_locale integration.
void main() async {
  // Initialize localization config
  const languages = (
    en: UiLanguage('en', 'English'),
    ru: UiLanguage('ru', 'Russian'),
  );

  LocalizationConfig.initialize(
    LocalizationConfig(
      supportedLanguages: [languages.en, languages.ru],
      fallbackLanguage: languages.en,
    ),
  );

  // Create localized support config with custom Russian translations
  final localizedSupportConfig = SupportConfig(
    supportEmail: 'support@example.com',
    appName: 'My App',
    localization: {
      SupportLocalization.helloSupportTeam: LocalizedMap(
        value: {languages.en: 'Hello,', languages.ru: 'Добрый день,'},
      ),
      SupportLocalization.experiencingIssue: LocalizedMap(
        value: {
          languages.en: "I'm experiencing an issue with the {appName} app.",
          languages.ru: 'У меня возникла проблема с приложением {appName}.',
        },
      ),
      SupportLocalization.issueDescription: LocalizedMap(
        value: {
          languages.en: '**Issue Description:**',
          languages.ru: '**Описание проблемы:**',
        },
      ),
      SupportLocalization.appInformation: LocalizedMap(
        value: {
          languages.en: '**App Information:**',
          languages.ru: '**Информация о приложении:**',
        },
      ),
      SupportLocalization.deviceInformation: LocalizedMap(
        value: {
          languages.en: '**Device Information:**',
          languages.ru: '**Информация об устройстве:**',
        },
      ),
      SupportLocalization.contactEmail: LocalizedMap(
        value: {
          languages.en: '**Contact Email:**',
          languages.ru: '**Email для связи:**',
        },
      ),
      SupportLocalization.userName: LocalizedMap(
        value: {
          languages.en: '**User Name:**',
          languages.ru: '**Имя пользователя:**',
        },
      ),
      SupportLocalization.additionalContext: LocalizedMap(
        value: {
          languages.en: '**Additional Context:**',
          languages.ru: '**Дополнительный контекст:**',
        },
      ),
      SupportLocalization.additionalDetails: LocalizedMap(
        value: {
          languages.en: '**Additional Details:**',
          languages.ru: '**Дополнительные детали:**',
        },
      ),
      SupportLocalization.provideAdditionalContext: LocalizedMap(
        value: {
          languages.en:
              'Please provide any additional context about your issue below:',
          languages.ru:
              'Пожалуйста, предоставьте дополнительную информацию о вашей проблеме ниже:',
        },
      ),
      SupportLocalization.sentFromApp: LocalizedMap(
        value: {
          languages.en: 'Sent from {appName} app',
          languages.ru: 'Отправлено из приложения {appName}',
        },
      ),
      SupportLocalization.appFeedback: LocalizedMap(
        value: {
          languages.en: 'App Feedback',
          languages.ru: 'Отзыв о приложении',
        },
      ),
      SupportLocalization.userFeedbackOrBugReport: LocalizedMap(
        value: {
          languages.en: 'User feedback or bug report',
          languages.ru: 'Отзыв пользователя или сообщение об ошибке',
        },
      ),
      SupportLocalization.notProvided: LocalizedMap(
        value: {languages.en: 'Not provided', languages.ru: 'Не указано'},
      ),
      SupportLocalization.unknown: LocalizedMap(
        value: {languages.en: 'Unknown', languages.ru: 'Неизвестно'},
      ),
      SupportLocalization.version: LocalizedMap(
        value: {languages.en: 'Version', languages.ru: 'Версия'},
      ),
      SupportLocalization.build: LocalizedMap(
        value: {languages.en: 'Build', languages.ru: 'Сборка'},
      ),
      SupportLocalization.package: LocalizedMap(
        value: {languages.en: 'Package', languages.ru: 'Пакет'},
      ),
      SupportLocalization.appName: LocalizedMap(
        value: {languages.en: 'App Name', languages.ru: 'Название приложения'},
      ),
      SupportLocalization.platform: LocalizedMap(
        value: {languages.en: 'Platform', languages.ru: 'Платформа'},
      ),
      SupportLocalization.model: LocalizedMap(
        value: {languages.en: 'Model', languages.ru: 'Модель'},
      ),
      SupportLocalization.osVersion: LocalizedMap(
        value: {languages.en: 'OS Version', languages.ru: 'Версия ОС'},
      ),
      SupportLocalization.manufacturer: LocalizedMap(
        value: {languages.en: 'Manufacturer', languages.ru: 'Производитель'},
      ),
    },
  );

  // Example: Use the localized support system
  await _sendLocalizedSupportEmail(localizedSupportConfig);
}

/// Example function showing how to send a localized support email
Future<void> _sendLocalizedSupportEmail(final SupportConfig config) async {
  // Send a comprehensive support email with English localization
  final success = await SupportManager.instance.sendSupportEmail(
    config: config,
    subject: 'Bug Report',
    description: 'The app crashes when I try to save data.',
    userEmail: 'user@example.com',
    userName: 'John Doe',
    additionalContext: {
      'Steps to reproduce': '1. Open app\n2. Try to save\n3. App crashes',
      'Expected behavior': 'Data should save successfully',
    },
    language: const UiLanguage('en', 'English'),
  );

  if (success) {
    print('English localized support email sent successfully!');
  } else {
    print('Failed to send English localized support email.');
  }

  // Send a comprehensive support email with Russian localization
  final russianSuccess = await SupportManager.instance.sendSupportEmail(
    config: config,
    subject: 'Сообщение об ошибке',
    description: 'Приложение вылетает при попытке сохранить данные.',
    userEmail: 'user@example.com',
    userName: 'Иван Иванов',
    additionalContext: {
      'Шаги для воспроизведения':
          '1. Открыть приложение\n2. Попытаться сохранить\n3. Приложение вылетает',
      'Ожидаемое поведение': 'Данные должны сохраняться успешно',
    },
    language: const UiLanguage('ru', 'Russian'),
  );

  if (russianSuccess) {
    print('Russian localized support email sent successfully!');
  } else {
    print('Failed to send Russian localized support email.');
  }

  // Send a simple support email with localized defaults (English)
  final simpleSuccess = await SupportManager.instance.sendSimpleSupportEmail(
    config: config,
    userEmail: 'user@example.com',
    additionalInfo: 'Quick feedback about the new feature.',
    language: const UiLanguage('en', 'English'),
  );

  if (simpleSuccess) {
    print('English localized simple support email sent successfully!');
  } else {
    print('Failed to send English localized simple support email.');
  }

  // Send a simple support email with localized defaults (Russian)
  final simpleRussianSuccess = await SupportManager.instance
      .sendSimpleSupportEmail(
        config: config,
        userEmail: 'user@example.com',
        additionalInfo: 'Быстрый отзыв о новой функции.',
        language: const UiLanguage('ru', 'Russian'),
      );

  if (simpleRussianSuccess) {
    print('Russian localized simple support email sent successfully!');
  } else {
    print('Failed to send Russian localized simple support email.');
  }
}
