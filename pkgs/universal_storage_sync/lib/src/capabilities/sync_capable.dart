import '../config/storage_config.dart';
import '../exceptions/storage_exceptions.dart';

/// {@template sync_capable}
/// Mixin for storage providers that support remote synchronization.
/// Provides standardized sync operations and conflict resolution.
/// {@endtemplate}
mixin SyncCapable {
  /// Indicates if the provider supports remote synchronization
  bool get supportsSync => true;

  /// Synchronizes local data with remote repository
  Future<void> sync({
    String? pullMergeStrategy,
    String? pushConflictStrategy,
  });

  /// Pushes local changes to remote repository
  Future<void> push({String? strategy}) async {
    throw const UnsupportedOperationException(
      'Push operation must be implemented by the provider',
    );
  }

  /// Pulls remote changes to local repository
  Future<void> pull({String? strategy}) async {
    throw const UnsupportedOperationException(
      'Pull operation must be implemented by the provider',
    );
  }

  /// Checks if there are local changes to be synchronized
  Future<bool> hasLocalChanges() async {
    throw const UnsupportedOperationException(
      'hasLocalChanges must be implemented by the provider',
    );
  }

  /// Checks if there are remote changes to be synchronized
  Future<bool> hasRemoteChanges() async {
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
  Future<void> forceSync({bool preferLocal = false}) async {
    if (preferLocal) {
      await push(strategy: 'force');
    } else {
      await pull(strategy: 'force');
    }
  }

  /// Resolves conflicts during synchronization
  Future<void> resolveConflicts({
    ConflictResolutionStrategy? strategy,
  }) async {
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
