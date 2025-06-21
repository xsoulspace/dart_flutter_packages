import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:oauth2/oauth2.dart' as oauth2;

import '../models/git_platform.dart';

/// Extension type that represents an OAuth access token.
///
/// Type-safe wrapper around OAuth access tokens to prevent mixing
/// with other string types at compile time.
extension type const OAuthAccessToken(String value) {
  /// Creates an OAuth access token from JSON data.
  ///
  /// Decodes the JSON value to a string and wraps it in an OAuthAccessToken.
  ///
  /// Parameters:
  /// - [value]: The JSON data to decode, typically a string or dynamic value.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthAccessToken.fromJson(final dynamic value) =>
      OAuthAccessToken(jsonDecodeString(value));

  /// Converts the OAuth access token to JSON format.
  ///
  /// Returns the underlying string value, which can be directly serialized
  /// to JSON.
  String toJson() => value;

  /// Whether the OAuth access token is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether the OAuth access token is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Get a safe representation for logging (first 8 characters + ...).
  String get safeRepresentation => isEmpty
      ? 'empty'
      : '${value.substring(0, value.length < 8 ? value.length : 8)}...';

  /// Returns this OAuth access token if not empty, otherwise returns the
  /// provided fallback.
  ///
  /// Useful for providing default values when an OAuth access token might be
  /// empty.
  ///
  /// [other]: The fallback OAuth access token to use if this one is empty.
  OAuthAccessToken whenEmptyUse(final OAuthAccessToken other) =>
      isEmpty ? other : this;

  /// An empty OAuth access token instance.
  ///
  /// Represents an OAuth access token with no information.
  static const empty = OAuthAccessToken('');
}

/// Extension type that represents an OAuth refresh token.
///
/// Type-safe wrapper around OAuth refresh tokens to prevent mixing
/// with other string types at compile time.
extension type const OAuthRefreshToken(String value) {
  /// Creates an OAuth refresh token from JSON data.
  ///
  /// Decodes the JSON value to a string and wraps it in an OAuthRefreshToken.
  ///
  /// Parameters:
  /// - [value]: The JSON data to decode, typically a string or dynamic value.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthRefreshToken.fromJson(final dynamic value) =>
      OAuthRefreshToken(jsonDecodeString(value));

  /// Converts the OAuth refresh token to JSON format.
  ///
  /// Returns the underlying string value, which can be directly serialized
  /// to JSON.
  String toJson() => value;

  /// Whether the OAuth refresh token is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether the OAuth refresh token is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns this OAuth refresh token if not empty, otherwise returns the
  /// provided fallback.
  ///
  /// Useful for providing default values when an OAuth refresh token might be
  /// empty.
  ///
  /// [other]: The fallback OAuth refresh token to use if this one is empty.
  OAuthRefreshToken whenEmptyUse(final OAuthRefreshToken other) =>
      isEmpty ? other : this;

  /// An empty OAuth refresh token instance.
  ///
  /// Represents an OAuth refresh token with no information.
  static const empty = OAuthRefreshToken('');
}

/// Extension type that represents stored OAuth credentials.
///
/// Contains OAuth access token, refresh token, expiration time, and scopes
/// for secure credential management. Provides type-safe access to credential
/// data with graceful handling of missing fields.
///
/// Uses from_json_to_json for type-safe JSON handling.
extension type const StoredCredentials(Map<String, dynamic> value) {
  /// Creates stored credentials from JSON data.
  ///
  /// Decodes the JSON value to a map and wraps it in a StoredCredentials.
  ///
  /// Parameters:
  /// - [jsonData]: The JSON data to decode, typically a map or dynamic value.
  // ignore: avoid_annotating_with_dynamic
  factory StoredCredentials.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return StoredCredentials(map);
  }

  /// Create stored credentials with required fields
  factory StoredCredentials.create({
    required final OAuthAccessToken accessToken,
    final OAuthRefreshToken? refreshToken,
    final DateTime? expiresAt,
    final List<String>? scopes,
  }) => StoredCredentials({
    'access_token': accessToken.value,
    'refresh_token': refreshToken?.value,
    'expires_at': expiresAt?.toIso8601String(),
    'scopes': scopes,
  });

  /// Create stored credentials from oauth2 library credentials
  factory StoredCredentials.fromOauth2Credentials(
    final oauth2.Credentials credentials,
  ) => StoredCredentials.create(
    accessToken: OAuthAccessToken(credentials.accessToken),
    refreshToken: credentials.refreshToken != null
        ? OAuthRefreshToken(credentials.refreshToken!)
        : null,
    expiresAt: credentials.expiration,
    scopes: credentials.scopes,
  );

  /// OAuth access token
  OAuthAccessToken get accessToken =>
      OAuthAccessToken.fromJson(value['access_token']);

  /// OAuth refresh token (may be null)
  OAuthRefreshToken? get refreshToken {
    final tokenStr = jsonDecodeString(value['refresh_token']);
    if (tokenStr.isEmpty) return null;
    return OAuthRefreshToken(tokenStr);
  }

  /// Token expiration date (may be null)
  DateTime? get expiresAt {
    final dateStr = jsonDecodeString(value['expires_at']);
    return dateStr.isEmpty ? null : dateTimeFromIso8601String(dateStr);
  }

  /// OAuth scopes (may be null)
  List<String>? get scopes {
    final scopesList = jsonDecodeList(value['scopes']);
    if (scopesList.isEmpty) return null;
    return jsonDecodeListAs<String>(scopesList);
  }

  /// Whether the access token has expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Whether the access token is still valid
  bool get isValid => !isExpired && accessToken.isNotEmpty;

  /// Whether a refresh token is available
  bool get hasRefreshToken => refreshToken != null && refreshToken!.isNotEmpty;

  /// Whether the credentials have an expiration time set
  bool get hasExpiration => expiresAt != null;

  /// Whether the credentials include scopes
  bool get hasScopes => scopes != null && scopes!.isNotEmpty;

  /// Get the number of scopes (0 if no scopes)
  int get scopeCount => scopes?.length ?? 0;

  /// Check if a specific scope is included
  bool containsScope(final String scope) => scopes?.contains(scope) ?? false;

  /// Converts the stored credentials to JSON format.
  ///
  /// Returns the underlying map of strings to dynamic values directly.
  Map<String, dynamic> toJson() => value;

  /// An empty stored credentials instance.
  ///
  /// Represents stored credentials with no information.
  static const empty = StoredCredentials({});
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
