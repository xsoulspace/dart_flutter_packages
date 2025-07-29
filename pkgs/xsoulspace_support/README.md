# xsoulspace_support

A reusable Flutter package for email support functionality with automatic context collection and localization support.

## Features

- 📧 **Email Composition**: Compose and send support emails with pre-filled content
- 📱 **Device Information**: Automatic collection of device platform, model, and OS version
- 📦 **App Information**: Automatic collection of app version, build number, and package info
- 🎨 **Customizable Templates**: Support for custom email templates with variable substitution
- 🔧 **Configurable**: Flexible configuration for different app requirements
- 🛡️ **Error Handling**: Graceful fallbacks when information collection fails
- 📋 **Context Management**: Support for additional context and metadata
- 🌍 **Localization Support**: Full localization support using xsoulspace_locale with English and Russian translations

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  xsoulspace_support:
  xsoulspace_locale: ^0.2.0
```

## Quick Start

### Basic Usage

```dart
import 'package:xsoulspace_support/xsoulspace_support.dart';

// Configure support settings
const supportConfig = SupportConfig(
  supportEmail: 'support@yourapp.com',
  appName: 'My Awesome App',
);

// Send a simple support email
final success = await SupportManager.instance.sendSimpleSupportEmail(
  config: supportConfig,
  userEmail: 'user@example.com',
  additionalInfo: 'The app crashes when I try to save data.',
);

if (!success) {
  // Handle email client not available
  print('Email client not available');
}
```

### Advanced Usage

```dart
// Send a detailed support email
final success = await SupportManager.instance.sendSupportEmail(
  config: supportConfig,
  subject: 'App crashes on data save',
  description: 'The app crashes every time I try to save my data. This happens on the main screen after filling out the form.',
  userEmail: 'user@example.com',
  userName: 'John Doe',
  additionalContext: {
    'Screen': 'Main Form',
    'Action': 'Save Data',
    'Data Type': 'User Profile',
  },
);
```

### Custom Configuration

```dart
const customConfig = SupportConfig(
  supportEmail: 'support@yourapp.com',
  appName: 'My Awesome App',
  emailSubjectPrefix: 'Bug Report',
  includeDeviceInfo: true,
  includeAppInfo: true,
  additionalContext: {
    'Environment': 'Production',
    'Region': 'US',
  },
  emailTemplate: '''
Hello Support Team,

I'm experiencing an issue with {{appName}}.

**Issue:** {{subject}}
**Description:** {{description}}
**User:** {{userName}} ({{userEmail}})
**App Version:** {{appVersion}} ({{appBuild}})
**Device:** {{deviceModel}} on {{platform}} {{osVersion}}

Please help me resolve this issue.

Best regards,
{{userName}}
''',
);
```

## API Reference

### SupportConfig

Configuration class for the support system.

```dart
class SupportConfig {
  const SupportConfig({
    required String supportEmail,
    required String appName,
    String emailSubjectPrefix = 'Support Request',
    String? emailTemplate,
    bool includeDeviceInfo = true,
    bool includeAppInfo = true,
    Map<String, String>? additionalContext,
    Map<String, LocalizedMap>? localization, // Localization support
  });
}
```

### SupportManager

Main class for managing support requests.

#### Methods

- `sendSupportEmail()` - Send a comprehensive support email
- `sendSimpleSupportEmail()` - Send a simplified support email
- `createSupportRequest()` - Create a support request object

### EmailService

Service for email composition and sending.

#### Methods

- `sendEmail()` - Send an email with pre-filled content
- `composeEmailUrl()` - Compose a mailto URL
- `isValidEmail()` - Validate email address format
- `formatEmailBody()` - Format email body text
- `formatEmailSubject()` - Format email subject line

### Models

- `SupportRequest` - Complete support request data
- `AppInfo` - Application information
- `DeviceInfo` - Device information
- `SupportLocalization` - Localization keys and default values

## Localization Support

The package now supports full localization using `xsoulspace_locale`. All email templates, labels, and messages can be localized. Currently supports English and Russian languages.

### Setup

1. Add the `xsoulspace_locale` dependency:

```yaml
dependencies:
  xsoulspace_support: ^0.1.0
  xsoulspace_locale: ^0.2.0
```

2. Initialize the localization configuration:

```dart
import 'package:xsoulspace_locale/xsoulspace_locale.dart';

void main() {
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

  runApp(MyApp());
}
```

### Using Localized Support

```dart
import 'package:xsoulspace_support/xsoulspace_support.dart';
import 'package:xsoulspace_locale/xsoulspace_locale.dart';

// Send a localized support email (English)
final success = await SupportManager.instance.sendSupportEmail(
  config: supportConfig,
  subject: 'Bug Report',
  description: 'The app crashes when I try to save data.',
  userEmail: 'user@example.com',
  userName: 'John Doe',
  language: const UiLanguage('en', 'English'),
);

// Send a localized support email (Russian)
final russianSuccess = await SupportManager.instance.sendSupportEmail(
  config: supportConfig,
  subject: 'Сообщение об ошибке',
  description: 'Приложение вылетает при попытке сохранить данные.',
  userEmail: 'user@example.com',
  userName: 'Иван Иванов',
  language: const UiLanguage('ru', 'Russian'),
);

// Send a simple localized support email
final simpleSuccess = await SupportManager.instance.sendSimpleSupportEmail(
  config: supportConfig,
  userEmail: 'user@example.com',
  additionalInfo: 'Quick feedback about the new feature.',
  language: const UiLanguage('en', 'English'),
);
```

### Custom Localization

You can provide custom localization by passing a `Map<String, LocalizedMap>` to the `SupportConfig`:

```dart
final localizedSupportConfig = SupportConfig(
  supportEmail: 'support@example.com',
  appName: 'My App',
  localization: {
    SupportLocalization.helloSupportTeam: LocalizedMap(value: {
      const UiLanguage('en', 'English'): 'Hello Support Team,',
      const UiLanguage('ru', 'Russian'): 'Здравствуйте, команда поддержки,',
    }),
    SupportLocalization.experiencingIssue: LocalizedMap(value: {
      const UiLanguage('en', 'English'): "I'm experiencing an issue with the {appName} app.",
      const UiLanguage('ru', 'Russian'): 'У меня возникла проблема с приложением {appName}.',
    }),
    // ... add more custom translations
  },
);
```

### Localization Keys

The following localization keys are available in `SupportLocalization`:

#### Email Template Keys

- `helloSupportTeam` - Email greeting
- `experiencingIssue` - Issue description introduction
- `issueDescription` - Issue description label
- `appInformation` - App information section label
- `deviceInformation` - Device information section label
- `contactEmail` - Contact email label
- `userName` - User name label
- `additionalContext` - Additional context section label
- `additionalDetails` - Additional details section label
- `provideAdditionalContext` - Context request message
- `sentFromApp` - Email footer

#### Default Values

- `appFeedback` - Default subject for simple support emails
- `userFeedbackOrBugReport` - Default description for simple support emails
- `notProvided` - Fallback text for missing user information
- `unknown` - Fallback text for unknown values

#### Labels

- `version` - Version label
- `build` - Build label
- `package` - Package label
- `appName` - App name label
- `platform` - Platform label
- `model` - Model label
- `osVersion` - OS version label
- `manufacturer` - Manufacturer label

### Supported Languages

Currently supported languages:

- **English** (`en`) - Default language
- **Russian** (`ru`) - Full translation support

### Backward Compatibility

The localization support is fully backward compatible. If no `language` parameter is provided, the system will use the default language (English). If no custom localization is provided, the system will use the built-in default translations.

## Email Template Variables

When using custom email templates, you can use these variables:

- `{{subject}}` - Support request subject
- `{{description}}` - Support request description
- `{{userEmail}}` - User's email address
- `{{userName}}` - User's name
- `{{appVersion}}` - App version
- `{{appBuild}}` - App build number
- `{{appName}}` - App name
- `{{platform}}` - Device platform
- `{{deviceModel}}` - Device model
- `{{osVersion}}` - Operating system version

## Example

See the `example/localized_support_example.dart` file for a complete example of how to use the localized support system with both English and Russian translations.
