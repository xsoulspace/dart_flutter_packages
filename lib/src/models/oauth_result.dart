import 'package:from_json_to_json/from_json_to_json.dart';

import '../storage/credential_storage.dart';
import 'oauth_user.dart';

/// Extension type that represents OAuth error message.
///
/// Type-safe wrapper around OAuth error descriptions to prevent mixing
/// with other string types at compile time.
extension type const OAuthError(String value) {
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
/// Contains authentication credentials, user information, and error details
/// from OAuth flows. Provides type-safe access to result data with graceful
/// handling of missing fields.
///
/// Uses from_json_to_json for type-safe JSON handling.
extension type const OAuthResult(Map<String, dynamic> value) {
  factory OAuthResult.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return OAuthResult(map);
  }

  /// Create a successful OAuth result
  factory OAuthResult.success({
    required final StoredCredentials credentials,
    final OAuthUser? user,
  }) => OAuthResult({
    'credentials': credentials.toJson(),
    'user': user?.toJson(),
    'error': null,
    'success': true,
  });

  /// Create a failed OAuth result
  factory OAuthResult.failure({
    required final OAuthError error,
    final StoredCredentials? credentials,
    final OAuthUser? user,
  }) => OAuthResult({
    'credentials': credentials?.toJson(),
    'user': user?.toJson(),
    'error': error.value,
    'success': false,
  });

  /// Create result from individual components
  factory OAuthResult.create({
    required final StoredCredentials credentials,
    final OAuthUser? user,
    final OAuthError? error,
  }) => OAuthResult({
    'credentials': credentials.toJson(),
    'user': user?.toJson(),
    'error': error?.value,
    'success': error == null,
  });

  /// OAuth credentials from the authentication flow
  StoredCredentials get credentials {
    final credMap = jsonDecodeMap(value['credentials']);
    return StoredCredentials.fromJson(credMap);
  }

  /// User information from the OAuth provider (may be null)
  OAuthUser? get user {
    final userMap = value['user'];
    if (userMap == null) return null;
    return OAuthUser.fromJson(userMap);
  }

  /// Error message if authentication failed (may be null)
  OAuthError? get error {
    final errorStr = jsonDecodeString(value['error']);
    if (errorStr.isEmpty) return null;
    return OAuthError(errorStr);
  }

  /// Whether the authentication was successful
  bool get isSuccess => jsonDecodeBool(value['success']);

  /// Whether the authentication failed
  bool get isFailure => !isSuccess;

  /// Whether user information is available
  bool get hasUser => user != null;

  /// Whether an error occurred
  bool get hasError => error != null;

  /// Get error message or empty string if no error
  String get errorMessage => error?.value ?? '';

  /// Get user login or empty string if no user
  String get userLogin => user?.login ?? '';

  Map<String, dynamic> toJson() => value;

  static const empty = OAuthResult({});

  /// Default failure result for network errors
  static final networkFailure = OAuthResult.failure(
    error: OAuthError.networkError,
  );

  /// Default failure result for authorization denial
  static final authorizationFailure = OAuthResult.failure(
    error: OAuthError.authorizationDenied,
  );
}
