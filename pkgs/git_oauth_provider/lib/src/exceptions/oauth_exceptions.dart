/// Base exception for OAuth operations
abstract class OAuthException implements Exception {
  const OAuthException(this.message, [this.details]);

  final String message;
  final String? details;

  @override
  String toString() =>
      'OAuthException: $message${details != null ? ' ($details)' : ''}';
}

/// Authentication failed
class AuthenticationException extends OAuthException {
  const AuthenticationException(super.message, [super.details]);

  @override
  String toString() =>
      'AuthenticationException: $message${details != null ? ' ($details)' : ''}';
}

/// Invalid configuration
class ConfigurationException extends OAuthException {
  const ConfigurationException(super.message, [super.details]);

  @override
  String toString() =>
      'ConfigurationException: $message${details != null ? ' ($details)' : ''}';
}

/// Network/API errors
class ApiException extends OAuthException {
  const ApiException(super.message, [super.details]);

  const ApiException.network([String? details])
      : super('Network error occurred', details);

  const ApiException.unauthorized([String? details])
      : super('Unauthorized access', details);

  const ApiException.rateLimited([String? details])
      : super('Rate limit exceeded', details);

  const ApiException.notFound([String? details])
      : super('Resource not found', details);

  @override
  String toString() =>
      'ApiException: $message${details != null ? ' ($details)' : ''}';
}

/// Repository operation errors
class RepositoryException extends OAuthException {
  const RepositoryException(super.message, [super.details]);

  const RepositoryException.notFound(String repoName)
      : super('Repository not found', repoName);

  const RepositoryException.accessDenied(String repoName)
      : super('Access denied to repository', repoName);

  const RepositoryException.alreadyExists(String repoName)
      : super('Repository already exists', repoName);

  @override
  String toString() =>
      'RepositoryException: $message${details != null ? ' ($details)' : ''}';
}

/// Storage/credential related exceptions
class StorageException extends OAuthException {
  const StorageException(super.message, [super.details]);

  const StorageException.secureStorageUnavailable()
      : super('Secure storage is not available on this platform');

  const StorageException.corruptedData(String dataType)
      : super('Corrupted stored data', dataType);

  @override
  String toString() =>
      'StorageException: $message${details != null ? ' ($details)' : ''}';
}
