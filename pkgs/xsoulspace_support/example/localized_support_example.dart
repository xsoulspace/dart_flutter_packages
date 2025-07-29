import 'package:xsoulspace_locale/xsoulspace_locale.dart';
import 'package:xsoulspace_support/xsoulspace_support.dart';

/// Example demonstrating how to use the localized support system
/// with xsoulspace_locale integration.
void main() async {
  // Initialize localization config
  const languages = (
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

  // Create localized support config with default English strings
  // Note: The current implementation uses fallback strings
  // Full localization support will be implemented in future versions
  final localizedSupportConfig = SupportConfig(
    supportEmail: 'support@example.com',
    appName: 'My App',
    // For now, we'll use the default localization
    // Full LocalizedMap integration will be implemented later
  );

  // Example: Use the localized support system
  await _sendLocalizedSupportEmail(localizedSupportConfig);
}

/// Example function showing how to send a localized support email
Future<void> _sendLocalizedSupportEmail(final SupportConfig config) async {
  // Send a comprehensive support email with localization
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
  );

  if (success) {
    print('Localized support email sent successfully!');
  } else {
    print('Failed to send localized support email.');
  }

  // Send a simple support email with localized defaults
  final simpleSuccess = await SupportManager.instance.sendSimpleSupportEmail(
    config: config,
    userEmail: 'user@example.com',
    additionalInfo: 'Quick feedback about the new feature.',
  );

  if (simpleSuccess) {
    print('Localized simple support email sent successfully!');
  } else {
    print('Failed to send localized simple support email.');
  }
}
