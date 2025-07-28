/// {@template support_config}
/// Configuration for the support system.
///
/// Defines email templates, support contact information,
/// and customization options.
/// {@endtemplate}
class SupportConfig {
  /// {@macro support_config}
  const SupportConfig({
    required this.supportEmail,
    required this.appName,
    this.emailSubjectPrefix = 'Support Request',
    this.emailTemplate,
    this.includeDeviceInfo = true,
    this.includeAppInfo = true,
    this.additionalContext,
  });

  /// The support email address
  final String supportEmail;

  /// The name of the application
  final String appName;

  /// Prefix for email subjects (e.g., "Support Request: ")
  final String emailSubjectPrefix;

  /// Custom email template (optional)
  final String? emailTemplate;

  /// Whether to include device information in support emails
  final bool includeDeviceInfo;

  /// Whether to include app information in support emails
  final bool includeAppInfo;

  /// Additional context to include in all support emails
  final Map<String, String>? additionalContext;
}
