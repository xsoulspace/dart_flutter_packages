import 'package:from_json_to_json/from_json_to_json.dart';

import '../storage/credential_storage.dart';
import 'oauth_user.dart';

/// Extension type that represents OAuth error message.
///
/// Type-safe wrapper around OAuth error descriptions to prevent mixing
/// with other string types at compile time.
extension type const OAuthError(String value) {
  // ignore: avoid_annotating_with_dynamic
  factory OAuthError.fromJson(final dynamic value) =>
      OAuthError(jsonDecodeString(value));

  String toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;

  OAuthError whenEmptyUse(final OAuthError other) => isEmpty ? other : this;

  static const empty = OAuthError('');
  static const networkError = OAuthError('Network connection failed');
  static const authorizationDenied = OAuthError('User denied authorization');
  static const invalidCredentials = OAuthError('Invalid client credentials');
  static const tokenExpired = OAuthError('Access token has expired');
  static const invalidScope = OAuthError('Invalid or insufficient scope');
}

/// Extension type that represents the result of an OAuth authentication attempt.
///
/// Contains either successful authentication data (credentials and user info)
/// or error information if authentication failed.
///
/// Uses from_json_to_json for type-safe JSON handling.
extension type const OAuthResult(Map<String, dynamic> value) {
  // ignore: avoid_annotating_with_dynamic
  factory OAuthResult.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return OAuthResult(map);
  }

  /// Create a successful OAuth result
  factory OAuthResult.success({
    required final StoredCredentials credentials,
    required final OAuthUser user,
  }) => OAuthResult({
    'success': true,
    'credentials': credentials.toJson(),
    'user': user.toJson(),
  });

  /// Create a failed OAuth result
  factory OAuthResult.failure({required final OAuthError error}) =>
      OAuthResult({'success': false, 'error': error.toJson()});

  /// Whether the authentication was successful
  bool get isSuccess => jsonDecodeBool(value['success']);

  /// Whether the authentication failed
  bool get isFailure => !isSuccess;

  /// Authentication credentials (only available on success)
  StoredCredentials? get credentials {
    if (!isSuccess) return null;
    final credentialsData = value['credentials'];
    return credentialsData != null
        ? StoredCredentials.fromJson(credentialsData)
        : null;
  }

  /// Authenticated user information (only available on success)
  OAuthUser? get user {
    if (!isSuccess) return null;
    final userData = value['user'];
    return userData != null ? OAuthUser.fromJson(userData) : null;
  }

  /// Error information (only available on failure)
  OAuthError? get error {
    if (isSuccess) return null;
    final errorData = jsonDecodeString(value['error']);
    return errorData.isNotEmpty ? OAuthError(errorData) : null;
  }

  Map<String, dynamic> toJson() => value;

  static const empty = OAuthResult({});
}
