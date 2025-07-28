import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents support system configuration.
///
/// Defines email templates, support contact information,
/// and customization options for the support system.
///
/// Uses from_json_to_json for type-safe JSON handling.
///
/// Can be used to configure support email settings, app information,
/// and email templates for user support requests.
///
/// Provides functionality to handle JSON serialization/deserialization
/// and support system configuration management.
extension type const SupportConfig._(Map<String, dynamic> value) {
  /// {@macro support_config}
  factory SupportConfig({
    required final String supportEmail,
    required final String appName,
    final String emailSubjectPrefix = 'Support Request',
    final String? emailTemplate,
    final bool includeDeviceInfo = true,
    final bool includeAppInfo = true,
    final Map<String, String>? additionalContext,
  }) => SupportConfig._({
    'support_email': supportEmail,
    'app_name': appName,
    'email_subject_prefix': emailSubjectPrefix,
    'email_template': emailTemplate,
    'include_device_info': includeDeviceInfo,
    'include_app_info': includeAppInfo,
    'additional_context': additionalContext,
  });

  /// {@template support_config}
  /// Configuration for the support system.
  ///
  /// Defines email templates, support contact information,
  /// and customization options.
  /// {@endtemplate}
  factory SupportConfig.fromJson(final dynamic json) =>
      SupportConfig._(jsonDecodeMap(json));

  /// The support email address
  String get supportEmail => jsonDecodeString(value['support_email']);

  /// The name of the application
  String get appName => jsonDecodeString(value['app_name']);

  /// Prefix for email subjects (e.g., "Support Request: ")
  String get emailSubjectPrefix =>
      jsonDecodeString(value['email_subject_prefix']);

  /// Custom email template (optional)
  String get emailTemplate => jsonDecodeString(value['email_template']);

  /// Whether to include device information in support emails
  bool get includeDeviceInfo => jsonDecodeBool(value['include_device_info']);

  /// Whether to include app information in support emails
  bool get includeAppInfo => jsonDecodeBool(value['include_app_info']);

  /// Additional context to include in all support emails
  Map<String, String> get additionalContext =>
      jsonDecodeMapAs<String, String>(value['additional_context']);

  Map<String, dynamic> toJson() => value;

  static const empty = SupportConfig._({});
}
