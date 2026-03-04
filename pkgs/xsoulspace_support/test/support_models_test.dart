import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_locale/xsoulspace_locale.dart';
import 'package:xsoulspace_support/xsoulspace_support.dart';

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

  group('SupportRequest model', () {
    test('serializes and deserializes core fields', () {
      final request = SupportRequest(
        subject: 'Crash on startup',
        description: 'App crashes after splash',
        appInfo: AppInfo(
          version: '1.0.0',
          buildNumber: '42',
          packageName: 'dev.xsoulspace.app',
        ),
        deviceInfo: DeviceInfo(
          platform: 'android',
          model: 'Pixel',
          osVersion: '14',
        ),
        userEmail: 'user@example.com',
      );

      final decoded = SupportRequest.fromJson(request.toJson());

      expect(decoded.subject, request.subject);
      expect(decoded.description, request.description);
      expect(decoded.appInfo.packageName, 'dev.xsoulspace.app');
      expect(decoded.deviceInfo.platform, 'android');
      expect(decoded.userEmail, 'user@example.com');
    });
  });

  group('SupportConfig localization behavior', () {
    test('uses custom localization and falls back to default language', () {
      final config = SupportConfig(
        supportEmail: 'help@xsoulspace.dev',
        appName: 'XS App',
        localization: <String, LocalizedMap>{
          'greeting': LocalizedMap(<UiLanguage, String>{english: 'Hello'}),
        },
      );

      final localized = config.getLocalizedString(
        'greeting',
        russian,
        'fallback',
      );

      expect(localized, 'Hello');
    });

    test('SupportLocalization falls back when key is missing', () {
      final value = SupportLocalization.getLocalizedString(
        'missing_key',
        russian,
        'fallback',
      );

      expect(value, 'fallback');
    });
  });
}
