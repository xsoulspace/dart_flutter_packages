/// Conflict resolution strategies for remote synchronization.
enum ConflictResolutionStrategy {
  /// Local changes always take precedence over remote changes.
  clientAlwaysRight,

  /// Remote changes always take precedence over local changes.
  serverAlwaysRight,

  /// Throw exception for manual conflict resolution.
  manualResolution,

  /// Use timestamp-based resolution (last write wins).
  lastWriteWins,
}
