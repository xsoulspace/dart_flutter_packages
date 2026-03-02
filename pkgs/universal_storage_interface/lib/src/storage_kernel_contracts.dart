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
    required StorageNamespaceProfile namespaceProfile,
    required StorageService service,
  });
}

/// Optional migration endpoint capability for providers/bridges.
abstract interface class MigrationEndpoint {
  Future<MigrationPreparationResult> prepareMigration({
    required MigrationPlan plan,
  });

  Future<MigrationExecutionResult> executeMigration({
    required MigrationPlan plan,
  });

  /// Executes migration with explicit options when supported by the endpoint.
  ///
  /// This default implementation delegates to [executeMigration] so existing
  /// implementations remain compatible.
  Future<MigrationExecutionResult> executeMigrationWithOptions({
    required MigrationPlan plan,
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
    required MigrationPlan plan,
  });
}

/// Profile-aware kernel contract.
abstract interface class StorageKernelContract {
  Future<String?> read({
    required StorageNamespace namespace,
    required String path,
  });

  Future<FileOperationResult> write({
    required StorageNamespace namespace,
    required String path,
    required String content,
    String? message,
  });

  Future<FileOperationResult> delete({
    required StorageNamespace namespace,
    required String path,
    String? message,
  });

  Future<List<FileEntry>> list({
    required StorageNamespace namespace,
    String directoryPath = '.',
  });

  Stream<StorageObservationEvent> observe({
    StorageNamespace? namespace,
    String? pathPrefix,
  });

  Future<void> sync({StorageNamespace? namespace});

  Future<MigrationPreparationResult> prepareMigration({
    required MigrationPlan plan,
  });

  Future<MigrationExecutionResult> executeMigration({
    required MigrationPlan plan,
  });

  Future<MigrationExecutionResult> rollbackMigration({
    required MigrationPlan plan,
  });

  Future<StorageOperationResult> resolveDecision({
    required StorageDecision decision,
    required DecisionState targetState,
    String note = '',
  });
}
