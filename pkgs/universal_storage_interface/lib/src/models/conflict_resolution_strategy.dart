/// Conflict resolution strategies for sync operations.
enum ConflictResolutionStrategy {
  clientAlwaysRight,
  serverAlwaysRight,
  manualResolution,
  lastWriteWins,
}
