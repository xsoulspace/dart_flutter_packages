import 'models/models.dart';
import 'storage_service.dart';
import 'storage_service_contracts.dart';

/// Marker interface for local storage engines.
abstract interface class LocalEngine implements StorageProvider {}

/// Remote storage engine with capability declaration.
abstract interface class RemoteEngine implements StorageProvider {
  StorageCapabilities get declaredCapabilities;

  Future<StorageCapabilities> resolveCapabilities() async =>
      declaredCapabilities;
}

/// Optional sync orchestrator that can be plugged into kernel.
abstract interface class SyncEngine {
  Future<StorageOperationResult> syncNamespace({
    required final StorageNamespaceProfile namespaceProfile,
    required final StorageService service,
  });
}

/// Optional migration endpoint capability for providers/bridges.
abstract interface class MigrationEndpoint {
  Future<MigrationPreparationResult> prepareMigration({
    required final MigrationPlan plan,
  });

  Future<MigrationExecutionResult> executeMigration({
    required final MigrationPlan plan,
  });

  /// Executes migration with explicit options when supported by the endpoint.
  ///
  /// This default implementation delegates to [executeMigration] so existing
  /// implementations remain compatible.
  Future<MigrationExecutionResult> executeMigrationWithOptions({
    required final MigrationPlan plan,
    final bool overwrite = true,
    final bool dryRun = false,
    final bool collectDiffs = false,
    final bool pauseForDecisions = false,
    final Map<String, MigrationDecisionAction> decisionActions =
        const <String, MigrationDecisionAction>{},
    final Map<String, DecisionState> decisionStates =
        const <String, DecisionState>{},
  }) => executeMigration(plan: plan);

  Future<MigrationExecutionResult> rollbackMigration({
    required final MigrationPlan plan,
  });
}

/// Profile-aware kernel contract.
abstract interface class StorageKernelContract {
  Future<String?> read({
    required final StorageNamespace namespace,
    required final String path,
  });

  Future<FileOperationResult> write({
    required final StorageNamespace namespace,
    required final String path,
    required final String content,
    final String? message,
  });

  Future<FileOperationResult> delete({
    required final StorageNamespace namespace,
    required final String path,
    final String? message,
  });

  Future<List<FileEntry>> list({
    required final StorageNamespace namespace,
    final String directoryPath = '.',
  });

  Stream<StorageObservationEvent> observe({
    final StorageNamespace? namespace,
    final String? pathPrefix,
  });

  Future<void> sync({final StorageNamespace? namespace});

  Future<MigrationPreparationResult> prepareMigration({
    required final MigrationPlan plan,
  });

  Future<MigrationExecutionResult> executeMigration({
    required final MigrationPlan plan,
  });

  Future<MigrationExecutionResult> rollbackMigration({
    required final MigrationPlan plan,
  });

  Future<StorageOperationResult> resolveDecision({
    required final StorageDecision decision,
    required final DecisionState targetState,
    final String note = '',
  });
}
