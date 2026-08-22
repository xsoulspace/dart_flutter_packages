import 'package:meta/meta.dart';

/// Policy controlling deferred, coalesced git commits for
/// OfflineGitStorageProvider.
///
/// Git commits cost ~100ms+ each; committing per write makes write-heavy
/// workloads unusable. With batching enabled, file content is written to
/// disk immediately (reads are always consistent) while the commit is
/// deferred and coalesced into one batched commit.
@immutable
final class GitCommitBatching {
  const GitCommitBatching({
    this.maxDelay = const Duration(milliseconds: 500),
    this.maxPendingOperations = 50,
  });

  /// Maximum time to hold an uncommitted mutation before flushing.
  final Duration maxDelay;

  /// Flush immediately once this many mutations are pending.
  final int maxPendingOperations;

  /// Batching disabled: every mutation commits synchronously.
  static const disabled = GitCommitBatching(maxDelay: Duration.zero);
}
