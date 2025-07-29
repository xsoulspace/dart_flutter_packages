import 'package:xsoulspace_locale/xsoulspace_locale.dart';

/// {@template support_localization}
/// Localization keys and default values for the support system.
///
/// Provides localized strings for email templates, labels, and messages
/// used throughout the support functionality.
/// {@endtemplate}
class SupportLocalization {
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
  static const _en = UiLanguage('en', 'English');
  static const _ru = UiLanguage('ru', 'Russian');

  /// Default English localization map
  static Map<String, LocalizedMap> get defaultLocalization => {
    helloSupportTeam: LocalizedMap(value: {_en: 'Hello Support Team,'}),
    experiencingIssue: LocalizedMap(
      value: {_en: "I'm experiencing an issue with the {appName} app."},
    ),
    issueDescription: LocalizedMap(value: {_en: '**Issue Description:**'}),
    appInformation: LocalizedMap(value: {_en: '**App Information:**'}),
    deviceInformation: LocalizedMap(value: {_en: '**Device Information:**'}),
    contactEmail: LocalizedMap(value: {_en: '**Contact Email:**'}),
    userName: LocalizedMap(value: {_en: '**User Name:**'}),
    additionalContext: LocalizedMap(value: {_en: '**Additional Context:**'}),
    additionalDetails: LocalizedMap(value: {_en: '**Additional Details:**'}),
    provideAdditionalContext: LocalizedMap(
      value: {
        _en: 'Please provide any additional context about your issue below:',
      },
    ),
    sentFromApp: LocalizedMap(value: {_en: 'Sent from {appName} app'}),
    appFeedback: LocalizedMap(value: {_en: 'App Feedback'}),
    userFeedbackOrBugReport: LocalizedMap(
      value: {_en: 'User feedback or bug report'},
    ),
    notProvided: LocalizedMap(value: {_en: 'Not provided'}),
    unknown: LocalizedMap(value: {_en: 'Unknown'}),
    version: LocalizedMap(value: {_en: 'Version'}),
    build: LocalizedMap(value: {_en: 'Build'}),
    package: LocalizedMap(value: {_en: 'Package'}),
    appName: LocalizedMap(value: {_en: 'App Name'}),
    platform: LocalizedMap(value: {_en: 'Platform'}),
    model: LocalizedMap(value: {_en: 'Model'}),
    osVersion: LocalizedMap(value: {_en: 'OS Version'}),
    manufacturer: LocalizedMap(value: {_en: 'Manufacturer'}),
  };

  /// Helper method to get localized string with fallback
  static String getLocalizedString(
    final LocalizedMap localization,
    final String key,
    final String fallback,
  ) {
    // For now, return the fallback since we need to restructure the localization
    // This will be implemented properly once we understand the correct structure
    return fallback;
  }
}
