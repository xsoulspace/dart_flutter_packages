/// Base exception for all storage-related errors.
sealed class StorageException implements Exception {
  /// {@macro storage_exception}
  const StorageException(this.message);

  /// Error message for the exception.
  final String message;

  @override
  String toString() => 'StorageException: $message';
}

/// Authentication-related error.
class AuthenticationException extends StorageException {
  /// Creates an authentication exception.
  const AuthenticationException(super.message);
  @override
  String toString() => 'AuthenticationException: $message';
}

/// File not found error.
class FileNotFoundException extends StorageException {
  /// Creates a file-not-found exception.
  const FileNotFoundException(super.message);
  @override
  String toString() => 'FileNotFoundException: $message';
}

/// File exists error.
class FileAlreadyExistsException extends StorageException {
  /// Creates a file-already-exists exception.
  const FileAlreadyExistsException(super.message);
  @override
  String toString() => 'FileAlreadyExistsException: $message';
}

/// Network error.
class NetworkException extends StorageException {
  /// Creates a network exception.
  const NetworkException(super.message);
  @override
  String toString() => 'NetworkException: $message';
}

/// Git conflict error.
class GitConflictException extends StorageException {
  /// Creates a git-conflict exception.
  const GitConflictException(super.message);
  @override
  String toString() => 'GitConflictException: $message';
}

/// Sync conflict error.
class SyncConflictException extends StorageException {
  /// Creates a sync-conflict exception.
  const SyncConflictException(super.message);
  @override
  String toString() => 'SyncConflictException: $message';
}

/// Operation not supported error.
class UnsupportedOperationException extends StorageException {
  /// Creates an unsupported-operation exception.
  const UnsupportedOperationException(super.message);
  @override
  String toString() => 'UnsupportedOperationException: $message';
}

/// Remote operation exceptions
class RemoteNotFoundException extends NetworkException {
  const RemoteNotFoundException(super.message);
  @override
  String toString() => 'RemoteNotFoundException: $message';
}

class AuthenticationFailedException extends AuthenticationException {
  const AuthenticationFailedException(super.message);
  @override
  String toString() => 'AuthenticationFailedException: $message';
}

class MergeConflictException extends GitConflictException {
  const MergeConflictException(super.message);
  @override
  String toString() => 'MergeConflictException: $message';
}

class NetworkTimeoutException extends NetworkException {
  const NetworkTimeoutException(super.message);
  @override
  String toString() => 'NetworkTimeoutException: $message';
}

class RemoteAccessDeniedException extends AuthenticationException {
  const RemoteAccessDeniedException(super.message);
  @override
  String toString() => 'RemoteAccessDeniedException: $message';
}

/// GitHub API specific exceptions
class GitHubApiException extends NetworkException {
  const GitHubApiException(super.message);
  @override
  String toString() => 'GitHubApiException: $message';
}

class RepositoryCreationException extends GitHubApiException {
  const RepositoryCreationException(super.message);
  @override
  String toString() => 'RepositoryCreationException: $message';
}

class GitHubRateLimitException extends GitHubApiException {
  const GitHubRateLimitException(super.message);
  @override
  String toString() => 'GitHubRateLimitException: $message';
}

class ConfigurationException extends StorageException {
  const ConfigurationException(super.message);
  @override
  String toString() => 'ConfigurationException: $message';
}
