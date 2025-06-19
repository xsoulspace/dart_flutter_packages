// For PickResult sealed class

/// A sealed class representing the outcome of a directory picking operation.
sealed class PickResult {}

/// Represents a successful directory pick.
class PickSuccess extends PickResult {
  /// The absolute path of the selected directory.
  final String path;

  PickSuccess(this.path);
}

/// Represents a failed directory pick.
class PickFailure extends PickResult {
  /// The reason for the failure.
  final FailureReason reason;

  PickFailure(this.reason);
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
