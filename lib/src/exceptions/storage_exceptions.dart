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
