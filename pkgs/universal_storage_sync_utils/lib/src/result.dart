import 'package:universal_storage_sync/universal_storage_sync.dart';

// For PickResult sealed class

/// A sealed class representing the outcome of a directory picking operation.
sealed class PickResult {}

/// {@template pick_success}
/// Represents a successful folder pick.
/// {@endtemplate}
class PickSuccess extends PickResult {
  /// {@macro pick_success}
  PickSuccess(this.path, {this.macOSBookmark});

  /// The path of the selected directory.
  final String path;

  /// An optional security-scoped bookmark for macOS.
  final MacOSBookmark? macOSBookmark;
}

/// Represents a failed folder pick.
class PickFailure extends PickResult {
  /// {@macro pick_failure}
  PickFailure(this.reason);

  /// The reason for the failure.
  final FailureReason reason;
}

/// Represents the user cancelling the directory picker.
class PickCancelled extends PickResult {}

/// An enum describing the possible reasons for a `PickFailure`.
enum FailureReason {
  /// The user denied the necessary permissions to access the folder.
  permissionDenied,

  /// The selected path is not a writable directory.
  pathNotWritable,

  /// The folder picking operation is not supported on the current platform.
  platformNotSupported,
}
