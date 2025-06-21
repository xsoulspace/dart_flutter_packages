import '../models/models.dart';
import '../storage_exceptions.dart';

/// {@template remote_sync_capable}
/// Mixin for storage providers that support remote synchronization.
/// Provides standardized sync operations and conflict resolution.
/// {@endtemplate}
mixin RemoteSyncCapable {
  /// Indicates if the provider supports remote synchronization
  bool get supportsSync => true;

  /// Synchronizes local data with remote repository
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  });

  /// Pushes local changes to remote repository
  Future<void> push({final String? strategy}) {
    throw const UnsupportedOperationException(
      'Push operation must be implemented by the provider',
    );
  }

  /// Pulls remote changes to local repository
  Future<void> pull({final String? strategy}) {
    throw const UnsupportedOperationException(
      'Pull operation must be implemented by the provider',
    );
  }

  /// Checks if there are local changes to be synchronized
  Future<bool> hasLocalChanges() {
    throw const UnsupportedOperationException(
      'hasLocalChanges must be implemented by the provider',
    );
  }

  /// Checks if there are remote changes to be synchronized
  Future<bool> hasRemoteChanges() {
    throw const UnsupportedOperationException(
      'hasRemoteChanges must be implemented by the provider',
    );
  }

  /// Gets the current synchronization status
  Future<SyncStatus> getSyncStatus() async {
    final hasLocal = await hasLocalChanges();
    final hasRemote = await hasRemoteChanges();

    if (hasLocal && hasRemote) {
      return SyncStatus.conflicted;
    } else if (hasLocal) {
      return SyncStatus.localChanges;
    } else if (hasRemote) {
      return SyncStatus.remoteChanges;
    } else {
      return SyncStatus.synchronized;
    }
  }

  /// Forces a complete synchronization, potentially losing local changes
  Future<void> forceSync({final bool preferLocal = false}) async {
    if (preferLocal) {
      await push(strategy: 'force');
    } else {
      await pull(strategy: 'force');
    }
  }

  /// Resolves conflicts during synchronization
  Future<void> resolveConflicts({final ConflictResolutionStrategy? strategy}) {
    throw const UnsupportedOperationException(
      'resolveConflicts must be implemented by the provider',
    );
  }
}

/// {@template sync_status}
/// Represents the synchronization status between local and remote repositories.
/// {@endtemplate}
enum SyncStatus {
  /// Local and remote are synchronized
  synchronized,

  /// Local has changes not yet pushed
  localChanges,

  /// Remote has changes not yet pulled
  remoteChanges,

  /// Both local and remote have changes (conflict)
  conflicted,

  /// Sync status cannot be determined
  unknown,
}
