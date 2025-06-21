import 'package:from_json_to_json/from_json_to_json.dart';

import '../storage/credential_storage.dart';
import 'oauth_user.dart';

/// Extension type that represents OAuth error message.
///
/// Type-safe wrapper around OAuth error descriptions to prevent mixing
/// with other string types at compile time.
extension type const OAuthError(String value) {
  /// Creates an OAuthError from JSON data.
  ///
  /// Decodes the JSON value to a string and wraps it in an OAuthError.
  ///
  /// Parameters:
  /// - [value]: The JSON data to decode, typically a string or dynamic value.
  ///
  /// Returns:
  /// - An OAuthError instance containing the decoded error message.
  // ignore: avoid_annotating_with_dynamic
  factory OAuthError.fromJson(final dynamic value) =>
      OAuthError(jsonDecodeString(value));

  /// Converts the OAuthError to JSON format.
  ///
  /// Returns the underlying string value as JSON.
  ///
  /// Returns:
  /// - The error message as a JSON string.
  String toJson() => value;

  /// Checks if the error message is empty.
  ///
  /// Returns:
  /// - `true` if the error message is empty, `false` otherwise.
  bool get isEmpty => value.isEmpty;

  /// Checks if the error message is not empty.
  ///
  /// Returns:
  /// - `true` if the error message is not empty, `false` otherwise.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns this error if not empty, otherwise returns the provided
  /// fallback error.
  ///
  /// Useful for providing default error messages when the current
  /// error is empty.
  ///
  /// Parameters:
  /// - [other]: The fallback OAuthError to use if this error is empty.
  ///
  /// Returns:
  /// - This OAuthError if not empty, otherwise the provided fallback error.
  OAuthError whenEmptyUse(final OAuthError other) => isEmpty ? other : this;

  /// An empty OAuthError instance.
  ///
  /// Represents an error with no message.
  static const empty = OAuthError('');

  /// A predefined error for network connection failures.
  ///
  /// Used when OAuth operations fail due to network connectivity issues.
  static const networkError = OAuthError('Network connection failed');

  /// A predefined error for when users deny authorization.
  ///
  /// Used when users explicitly cancel or deny the OAuth authorization request.
  static const authorizationDenied = OAuthError('User denied authorization');

  /// A predefined error for invalid client credentials.
  ///
  /// Used when the OAuth client ID, client secret, or other
  /// credentials are invalid.
  static const invalidCredentials = OAuthError('Invalid client credentials');

  /// A predefined error for expired access tokens.
  ///
  /// Used when the access token has expired and needs to be refreshed.
  static const tokenExpired = OAuthError('Access token has expired');

  /// A predefined error for invalid or insufficient scope.
  ///
  /// Used when the requested OAuth scope is invalid or the user hasn't granted
  /// sufficient permissions.
  static const invalidScope = OAuthError('Invalid or insufficient scope');
}

/// Extension type that represents the result of an OAuth authentication
/// attempt.
///
/// Contains either successful authentication data (credentials and user info)
/// or error information if authentication failed.
///
/// Uses from_json_to_json for type-safe JSON handling.
extension type const OAuthResult(Map<String, dynamic> value) {
  /// Creates an OAuthResult from JSON data.
  ///
  /// Decodes the JSON value to a map and wraps it in an OAuthResult.
  ///
  /// Parameters:
  /// - [jsonData]: The JSON data to decode, typically a map or dynamic value.
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

  /// Converts this [OAuthResult] to JSON.
  ///
  /// Returns the underlying map of strings to dynamic values directly.
  Map<String, dynamic> toJson() => value;

  /// An empty OAuthResult instance.
  ///
  /// Represents a result with no authentication data.
  static const empty = OAuthResult({});
}
