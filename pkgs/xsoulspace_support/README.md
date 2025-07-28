# xsoulspace_support

A reusable Flutter package for email support functionality with automatic context collection.

## Features

- 📧 **Email Composition**: Compose and send support emails with pre-filled content
- 📱 **Device Information**: Automatic collection of device platform, model, and OS version
- 📦 **App Information**: Automatic collection of app version, build number, and package info
- 🎨 **Customizable Templates**: Support for custom email templates with variable substitution
- 🔧 **Configurable**: Flexible configuration for different app requirements
- 🛡️ **Error Handling**: Graceful fallbacks when information collection fails
- 📋 **Context Management**: Support for additional context and metadata

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
