import 'package:oauth2/oauth2.dart' as oauth2;

import '../models/git_platform.dart';

/// Stored OAuth credentials
class StoredCredentials {
  const StoredCredentials({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scopes,
  });

  factory StoredCredentials.fromJson(final Map<String, dynamic> json) =>
      StoredCredentials(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String?,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        scopes: (json['scopes'] as List<dynamic>?)?.cast<String>(),
      );

  factory StoredCredentials.fromOauth2Credentials(
    final oauth2.Credentials credentials,
  ) => StoredCredentials(
    accessToken: credentials.accessToken,
    refreshToken: credentials.refreshToken,
    expiresAt: credentials.expiration,
    scopes: credentials.scopes,
  );

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final List<String>? scopes;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
    'scopes': scopes,
  };

  @override
  String toString() =>
      'StoredCredentials(token: ${accessToken.substring(0, 8)}..., expires: $expiresAt)';
}

/// Interface for storing OAuth credentials securely
abstract class CredentialStorage {
  /// Store credentials for a platform
  Future<void> storeCredentials(
    final GitPlatform platform,
    final StoredCredentials credentials,
  );

  /// Retrieve credentials for a platform
  Future<StoredCredentials?> getCredentials(final GitPlatform platform);

  /// Clear credentials for a platform
  Future<void> clearCredentials(final GitPlatform platform);

  /// Clear all stored credentials
  Future<void> clearAllCredentials();

  /// Check if credentials exist for a platform
  Future<bool> hasCredentials(final GitPlatform platform);
}
