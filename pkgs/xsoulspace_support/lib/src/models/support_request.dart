import 'package:from_json_to_json/from_json_to_json.dart';

import 'app_info.dart';
import 'device_info.dart';

/// Extension type that represents a support request.
///
/// Encapsulates all information needed for a support request including
/// user-provided information along with automatically collected app and device metadata.
///
/// Uses from_json_to_json for type-safe JSON handling.
///
/// Can be used to create, serialize, and deserialize support requests
/// for customer support systems.
///
/// Provides functionality to handle JSON serialization/deserialization
/// and support request data management.
extension type const SupportRequest._(Map<String, dynamic> value) {
  factory SupportRequest({
    required final String subject,
    required final String description,
    required final AppInfo appInfo,
    required final DeviceInfo deviceInfo,
    final String? userEmail,
    final String? userName,
    final Map<String, String>? additionalContext,
    final List<String>? attachments,
  }) => SupportRequest._({
    'subject': subject,
    'description': description,
    'app_info': appInfo.toJson(),
    'device_info': deviceInfo.toJson(),
    'user_email': userEmail,
    'user_name': userName,
    'additional_context': additionalContext,
    'attachments': attachments,
  });

  factory SupportRequest.fromJson(final dynamic json) =>
      SupportRequest._(jsonDecodeMap(json));

  /// The subject/title of the support request
  String get subject => jsonDecodeString(value['subject']);

  /// The detailed description of the issue or request
  String get description => jsonDecodeString(value['description']);

  /// Application information (version, build, etc.)
  AppInfo get appInfo => AppInfo.fromJson(value['app_info']);

  /// Device information (platform, model, OS, etc.)
  DeviceInfo get deviceInfo => DeviceInfo.fromJson(value['device_info']);

  /// User's email address for follow-up communication
  String get userEmail => jsonDecodeString(value['user_email']);

  /// User's name (optional)
  String get userName => jsonDecodeString(value['user_name']);

  /// Additional context or metadata about the request
  Map<String, String> get additionalContext =>
      jsonDecodeMapAs<String, String>(value['additional_context']);

  /// List of attachment file paths (if any)
  List<String> get attachments =>
      jsonDecodeListAs<String>(value['attachments']);

  Map<String, dynamic> toJson() => value;

  static const empty = SupportRequest._({});
}
