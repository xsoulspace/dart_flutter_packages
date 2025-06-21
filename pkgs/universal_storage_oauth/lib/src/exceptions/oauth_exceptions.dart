/// {@template oauth_exception}
/// Base exception for OAuth operations.
///
/// This abstract class provides a foundation for all OAuth-related exceptions,
/// including a message and optional details for better error context.
/// {@endtemplate}
abstract class OAuthException implements Exception {
  /// {@macro oauth_exception}
  const OAuthException(this.message, [this.details]);

  /// The primary error message.
  final String message;

  /// Optional additional details about the error.
  final String? details;

  @override
  String toString() =>
      'OAuthException: $message${details != null ? ' ($details)' : ''}';
}

/// {@template authentication_exception}
/// Exception thrown when OAuth authentication fails.
///
/// This exception is raised when the authentication process fails,
/// such as invalid credentials, expired tokens, or authentication flow errors.
/// {@endtemplate}
class AuthenticationException extends OAuthException {
  /// {@macro authentication_exception}
  const AuthenticationException(super.message, [super.details]);

  @override
  String toString() =>
      'AuthenticationException: '
      '$message${details != null ? ' ($details)' : ''}';
}

/// {@template configuration_exception}
/// Exception thrown when OAuth configuration is invalid.
///
/// This exception is raised when there are issues with OAuth configuration,
/// such as missing client ID, invalid redirect URIs, or malformed settings.
/// {@endtemplate}
class ConfigurationException extends OAuthException {
  /// {@macro configuration_exception}
  const ConfigurationException(super.message, [super.details]);

  @override
  String toString() =>
      'ConfigurationException: $message${details != null ? ' ($details)' : ''}';
}

/// {@template api_exception}
/// Exception thrown for network and API-related errors.
///
/// This exception covers various API-related issues including network errors,
/// HTTP status errors, rate limiting, and resource access problems.
/// {@endtemplate}
class ApiException extends OAuthException {
  /// {@macro api_exception}
  const ApiException(super.message, [super.details]);

  /// {@template api_exception_network}
  /// Network connectivity error.
  /// {@endtemplate}
  const ApiException.network([final String? details])
    : super('Network error occurred', details);

  /// {@template api_exception_unauthorized}
  /// Unauthorized access error (401).
  /// {@endtemplate}
  const ApiException.unauthorized([final String? details])
    : super('Unauthorized access', details);

  /// {@template api_exception_rate_limited}
  /// Rate limit exceeded error (429).
  /// {@endtemplate}
  const ApiException.rateLimited([final String? details])
    : super('Rate limit exceeded', details);

  /// {@template api_exception_not_found}
  /// Resource not found error (404).
  /// {@endtemplate}
  const ApiException.notFound([final String? details])
    : super('Resource not found', details);

  @override
  String toString() =>
      'ApiException: $message${details != null ? ' ($details)' : ''}';
}

/// {@template repository_exception}
/// Exception thrown for repository operation errors.
///
/// This exception covers repository-specific issues such as access denied,
/// repository not found, or conflicts during repository operations.
/// {@endtemplate}
class RepositoryException extends OAuthException {
  /// {@macro repository_exception}
  const RepositoryException(super.message, [super.details]);

  /// {@template repository_exception_not_found}
  /// Repository not found error.
  /// {@endtemplate}
  const RepositoryException.notFound(final String repoName)
    : super('Repository not found', repoName);

  /// {@template repository_exception_access_denied}
  /// Access denied to repository error.
  /// {@endtemplate}
  const RepositoryException.accessDenied(final String repoName)
    : super('Access denied to repository', repoName);

  /// {@template repository_exception_already_exists}
  /// Repository already exists error.
  /// {@endtemplate}
  const RepositoryException.alreadyExists(final String repoName)
    : super('Repository already exists', repoName);

  @override
  String toString() =>
      'RepositoryException: $message${details != null ? ' ($details)' : ''}';
}

/// {@template storage_exception}
/// Exception thrown for storage and credential-related errors.
///
/// This exception covers issues with secure storage, credential management,
/// and data corruption in stored OAuth tokens or configuration.
/// {@endtemplate}
class StorageException extends OAuthException {
  /// {@macro storage_exception}
  const StorageException(super.message, [super.details]);

  /// {@template storage_exception_secure_storage_unavailable}
  /// Secure storage not available on current platform.
  /// {@endtemplate}
  const StorageException.secureStorageUnavailable()
    : super('Secure storage is not available on this platform');

  /// {@template storage_exception_corrupted_data}
  /// Corrupted data in secure storage.
  /// {@endtemplate}
  const StorageException.corruptedData(final String dataType)
    : super('Corrupted stored data', dataType);

  @override
  String toString() =>
      'StorageException: $message${details != null ? ' ($details)' : ''}';
}
