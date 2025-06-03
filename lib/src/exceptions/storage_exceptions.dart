/// {@template storage_exception}
/// Base exception for all storage-related errors.
/// {@endtemplate}
abstract class StorageException implements Exception {
  /// {@macro storage_exception}
  const StorageException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'StorageException: $message';
}

/// {@template authentication_exception}
/// Thrown when authentication fails or is required.
/// {@endtemplate}
class AuthenticationException extends StorageException {
  /// {@macro authentication_exception}
  const AuthenticationException(super.message);

  @override
  String toString() => 'AuthenticationException: $message';
}

/// {@template file_not_found_exception}
/// Thrown when a requested file is not found.
/// {@endtemplate}
class FileNotFoundException extends StorageException {
  /// {@macro file_not_found_exception}
  const FileNotFoundException(super.message);

  @override
  String toString() => 'FileNotFoundException: $message';
}

/// {@template network_exception}
/// Thrown when network operations fail.
/// {@endtemplate}
class NetworkException extends StorageException {
  /// {@macro network_exception}
  const NetworkException(super.message);

  @override
  String toString() => 'NetworkException: $message';
}

/// {@template git_conflict_exception}
/// Thrown when Git operations encounter conflicts.
/// {@endtemplate}
class GitConflictException extends StorageException {
  /// {@macro git_conflict_exception}
  const GitConflictException(super.message);

  @override
  String toString() => 'GitConflictException: $message';
}

/// {@template sync_conflict_exception}
/// Thrown when synchronization encounters conflicts.
/// {@endtemplate}
class SyncConflictException extends StorageException {
  /// {@macro sync_conflict_exception}
  const SyncConflictException(super.message);

  @override
  String toString() => 'SyncConflictException: $message';
}

/// {@template unsupported_operation_exception}
/// Thrown when an operation is not supported by the provider.
/// {@endtemplate}
class UnsupportedOperationException extends StorageException {
  /// {@macro unsupported_operation_exception}
  const UnsupportedOperationException(super.message);

  @override
  String toString() => 'UnsupportedOperationException: $message';
}

// Stage 3: Remote operation exceptions

/// {@template remote_not_found_exception}
/// Thrown when a remote repository is not found or accessible.
/// {@endtemplate}
class RemoteNotFoundException extends NetworkException {
  /// {@macro remote_not_found_exception}
  const RemoteNotFoundException(super.message);

  @override
  String toString() => 'RemoteNotFoundException: $message';
}

/// {@template authentication_failed_exception}
/// Thrown when Git authentication fails for remote operations.
/// {@endtemplate}
class AuthenticationFailedException extends AuthenticationException {
  /// {@macro authentication_failed_exception}
  const AuthenticationFailedException(super.message);

  @override
  String toString() => 'AuthenticationFailedException: $message';
}

/// {@template merge_conflict_exception}
/// Thrown when Git merge operations encounter unresolvable conflicts.
/// {@endtemplate}
class MergeConflictException extends GitConflictException {
  /// {@macro merge_conflict_exception}
  const MergeConflictException(super.message);

  @override
  String toString() => 'MergeConflictException: $message';
}

/// {@template network_timeout_exception}
/// Thrown when network operations timeout.
/// {@endtemplate}
class NetworkTimeoutException extends NetworkException {
  /// {@macro network_timeout_exception}
  const NetworkTimeoutException(super.message);

  @override
  String toString() => 'NetworkTimeoutException: $message';
}

/// {@template remote_access_denied_exception}
/// Thrown when access to remote repository is denied.
/// {@endtemplate}
class RemoteAccessDeniedException extends AuthenticationException {
  /// {@macro remote_access_denied_exception}
  const RemoteAccessDeniedException(super.message);

  @override
  String toString() => 'RemoteAccessDeniedException: $message';
}

// Stage 4: GitHub API specific exceptions

/// {@template github_api_exception}
/// Thrown when GitHub API operations fail.
/// {@endtemplate}
class GitHubApiException extends NetworkException {
  /// {@macro github_api_exception}
  const GitHubApiException(super.message);

  @override
  String toString() => 'GitHubApiException: $message';
}

/// {@template repository_creation_exception}
/// Thrown when GitHub repository creation fails.
/// {@endtemplate}
class RepositoryCreationException extends GitHubApiException {
  /// {@macro repository_creation_exception}
  const RepositoryCreationException(super.message);

  @override
  String toString() => 'RepositoryCreationException: $message';
}

/// {@template github_rate_limit_exception}
/// Thrown when GitHub API rate limit is exceeded.
/// {@endtemplate}
class GitHubRateLimitException extends GitHubApiException {
  /// {@macro github_rate_limit_exception}
  const GitHubRateLimitException(super.message);

  @override
  String toString() => 'GitHubRateLimitException: $message';
}

/// {@template file_already_exists_exception}
/// Thrown when attempting to create a file that already exists.
/// {@endtemplate}
class FileAlreadyExistsException extends StorageException {
  /// {@macro file_already_exists_exception}
  const FileAlreadyExistsException(super.message);

  @override
  String toString() => 'FileAlreadyExistsException: $message';
}

/// {@template configuration_exception}
/// Thrown when configuration is invalid or missing.
/// {@endtemplate}
class ConfigurationException extends StorageException {
  /// {@macro configuration_exception}
  const ConfigurationException(super.message);

  @override
  String toString() => 'ConfigurationException: $message';
}
