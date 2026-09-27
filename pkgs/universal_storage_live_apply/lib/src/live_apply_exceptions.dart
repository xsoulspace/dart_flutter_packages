/// Raised when a rollback refuses because a journaled path changed AFTER the
/// run applied — the state no longer matches what the inverse was proven
/// against. The offending paths are listed; nothing is mutated.
///
/// These extend [Exception] rather than the interface's sealed
/// [StorageException] hierarchy: sealed classes cannot be extended outside
/// their library, and live-apply refusals are a distinct failure family.
class LiveApplyDriftException implements Exception {
  /// {@macro live_apply_drift_exception}
  const LiveApplyDriftException(this.message, this.paths);

  /// Human-readable refusal reason.
  final String message;

  /// The paths whose current content differs from the recorded post state.
  final List<String> paths;

  @override
  String toString() => 'LiveApplyDriftException: $message';
}

/// Raised when live apply refuses BEFORE mutating: a prior state too large
/// to snapshot under the configured limit, or an operation on a run that is
/// already closed.
class LiveApplyRefusalException implements Exception {
  /// {@macro live_apply_refusal_exception}
  const LiveApplyRefusalException(this.message);

  /// Human-readable refusal reason.
  final String message;

  @override
  String toString() => 'LiveApplyRefusalException: $message';
}
