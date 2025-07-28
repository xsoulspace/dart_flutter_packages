import 'app_info.dart';
import 'device_info.dart';

/// {@template support_request}
/// Encapsulates all information needed for a support request.
///
/// This model contains user-provided information along with
/// automatically collected app and device metadata.
/// {@endtemplate}
class SupportRequest {
  /// {@macro support_request}
  const SupportRequest({
    required this.subject,
    required this.description,
    required this.appInfo,
    required this.deviceInfo,
    this.userEmail,
    this.userName,
    this.additionalContext,
    this.attachments,
  });

  /// The subject/title of the support request
  final String subject;

  /// The detailed description of the issue or request
  final String description;

  /// Application information (version, build, etc.)
  final AppInfo appInfo;

  /// Device information (platform, model, OS, etc.)
  final DeviceInfo deviceInfo;

  /// User's email address for follow-up communication
  final String? userEmail;

  /// User's name (optional)
  final String? userName;

  /// Additional context or metadata about the request
  final Map<String, String>? additionalContext;

  /// List of attachment file paths (if any)
  final List<String>? attachments;
}
