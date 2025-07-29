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
- 🌍 **Localization Support**: Full localization support using xsoulspace_locale

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  xsoulspace_support:
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
    LocalizedMap? localization, // New localization parameter
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

The package now supports full localization using `xsoulspace_locale`. All email templates, labels, and messages can be localized.

### Setup

1. Add the `xsoulspace_locale` dependency:

```yaml
dependencies:
  xsoulspace_support: ^0.1.0
  xsoulspace_locale: ^0.0.2
```

2. Initialize the localization configuration:

```dart
import 'package:xsoulspace_locale/xsoulspace_locale.dart';

void main() {
  final languages = (
    en: UiLanguage('en', 'English'),
    es: UiLanguage('es', 'Español'),
    fr: UiLanguage('fr', 'Français'),
  );

  LocalizationConfig.initialize(
    LocalizationConfig(
      supportedLanguages: [languages.en, languages.es, languages.fr],
      fallbackLanguage: languages.en,
    ),
  );

  runApp(MyApp());
}
```

### Localized Support Configuration

```dart
import 'package:xsoulspace_support/xsoulspace_support.dart';
import 'package:xsoulspace_locale/xsoulspace_locale.dart';

// Create localized support config
final localizedSupportConfig = SupportConfig(
  supportEmail: 'support@example.com',
  appName: 'My App',
  localization: LocalizedMap(
    value: {
      UiLanguage('en', 'English'): {
        SupportLocalization.helloSupportTeam: 'Hello Support Team,',
        SupportLocalization.experiencingIssue: "I'm experiencing an issue with the {appName} app.",
        SupportLocalization.issueDescription: '**Issue Description:**',
        SupportLocalization.appInformation: '**App Information:**',
        SupportLocalization.deviceInformation: '**Device Information:**',
        SupportLocalization.contactEmail: '**Contact Email:**',
        SupportLocalization.userName: '**User Name:**',
        SupportLocalization.additionalContext: '**Additional Context:**',
        SupportLocalization.additionalDetails: '**Additional Details:**',
        SupportLocalization.provideAdditionalContext: 'Please provide any additional context about your issue below:',
        SupportLocalization.sentFromApp: 'Sent from {appName} app',
        SupportLocalization.appFeedback: 'App Feedback',
        SupportLocalization.userFeedbackOrBugReport: 'User feedback or bug report',
        SupportLocalization.notProvided: 'Not provided',
        SupportLocalization.unknown: 'Unknown',
        SupportLocalization.version: 'Version',
        SupportLocalization.build: 'Build',
        SupportLocalization.package: 'Package',
        SupportLocalization.appName: 'App Name',
        SupportLocalization.platform: 'Platform',
        SupportLocalization.model: 'Model',
        SupportLocalization.osVersion: 'OS Version',
        SupportLocalization.manufacturer: 'Manufacturer',
      },
      UiLanguage('es', 'Español'): {
        SupportLocalization.helloSupportTeam: 'Hola Equipo de Soporte,',
        SupportLocalization.experiencingIssue: 'Estoy experimentando un problema con la aplicación {appName}.',
        SupportLocalization.issueDescription: '**Descripción del Problema:**',
        SupportLocalization.appInformation: '**Información de la Aplicación:**',
        SupportLocalization.deviceInformation: '**Información del Dispositivo:**',
        SupportLocalization.contactEmail: '**Correo de Contacto:**',
        SupportLocalization.userName: '**Nombre de Usuario:**',
        SupportLocalization.additionalContext: '**Contexto Adicional:**',
        SupportLocalization.additionalDetails: '**Detalles Adicionales:**',
        SupportLocalization.provideAdditionalContext: 'Por favor proporcione cualquier contexto adicional sobre su problema a continuación:',
        SupportLocalization.sentFromApp: 'Enviado desde la aplicación {appName}',
        SupportLocalization.appFeedback: 'Comentarios de la Aplicación',
        SupportLocalization.userFeedbackOrBugReport: 'Comentarios del usuario o reporte de error',
        SupportLocalization.notProvided: 'No proporcionado',
        SupportLocalization.unknown: 'Desconocido',
        SupportLocalization.version: 'Versión',
        SupportLocalization.build: 'Compilación',
        SupportLocalization.package: 'Paquete',
        SupportLocalization.appName: 'Nombre de la Aplicación',
        SupportLocalization.platform: 'Plataforma',
        SupportLocalization.model: 'Modelo',
        SupportLocalization.osVersion: 'Versión del SO',
        SupportLocalization.manufacturer: 'Fabricante',
      },
    },
  ),
);
```

### Using Localized Support

```dart
// Send a localized support email
final success = await SupportManager.instance.sendSupportEmail(
  config: localizedSupportConfig,
  subject: 'Bug Report',
  description: 'The app crashes when I try to save data.',
  userEmail: 'user@example.com',
  userName: 'John Doe',
);

// Send a simple localized support email
final simpleSuccess = await SupportManager.instance.sendSimpleSupportEmail(
  config: localizedSupportConfig,
  userEmail: 'user@example.com',
  additionalInfo: 'Quick feedback about the new feature.',
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

### Backward Compatibility

The localization support is fully backward compatible. If no `LocalizedMap` is provided, the system will use default English strings.

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

## Generated Email Example

When a user sends a support email, it will look like this:

```
Subject: Support Request: App crashes on data save

Hello Support Team,

I'm experiencing an issue with the My Awesome App app.

**Issue Description:**
The app crashes every time I try to save my data. This happens on the main screen after filling out the form.

**App Information:**
- Version: 1.0.0 (1)
- Package: com.example.myapp
- App Name: My Awesome App

**Device Information:**
- Platform: iOS
- Model: iPhone 15 Pro
- OS Version: iOS 17.2
- Manufacturer: Apple

**Contact Email:** user@example.com
**User Name:** John Doe

**Additional Context:**
- Screen: Main Form
- Action: Save Data
- Data Type: User Profile

**Additional Details:**
Please provide any additional context about your issue below:




---
Sent from My Awesome App app
```

## Error Handling

The package includes comprehensive error handling:

- **Device Info Collection**: Falls back to "Unknown" values if collection fails
- **App Info Collection**: Falls back to default values if package info unavailable
- **Email Client**: Returns `false` if no email client is available
- **Template Processing**: Gracefully handles missing template variables

## Platform Support

- ✅ Android
- ✅ iOS
- ✅ Web
- ✅ macOS
- ✅ Windows
- ✅ Linux

## Dependencies

- `url_launcher` - For opening email clients
- `package_info_plus` - For app information
- `device_info_plus` - For device information

## License

This package is licensed under the MIT License.
