import 'package:universal_storage_interface/universal_storage_interface.dart';

import '../decision_store.dart';
import 'observation_hub.dart';

/// Handles prepare/execute/rollback migration flows on behalf of the kernel.
final class MigrationCoordinator {
  MigrationCoordinator({
    required final MigrationEndpoint? endpoint,
    required final DecisionStore decisionStore,
    required final ObservationHub observations,
  }) : _endpoint = endpoint,
       _decisionStore = decisionStore,
       _observations = observations;

  final MigrationEndpoint? _endpoint;
  final DecisionStore _decisionStore;
  final ObservationHub _observations;

  /// Runs migration preflight, either via the configured endpoint or
  /// local plan validation when no endpoint exists.
  Future<MigrationPreparationResult> prepare({
    required final MigrationPlan plan,
  }) async {
    MigrationPreparationResult result;
    if (_endpoint != null) {
      result = await _endpoint.prepareMigration(plan: plan);
      _emitPrepared(plan: plan, result: result);
      return result;
    }

    final issues = <String>[];
    final warnings = <String>[];

    if (plan.id.isEmpty) {
      issues.add('Migration id is empty.');
    }
    if (plan.sourceProfileHash.isEmpty || plan.targetProfileHash.isEmpty) {
      issues.add('Source/target profile hashes must be provided.');
    }
    if (plan.sourceProfileHash == plan.targetProfileHash) {
      warnings.add('Source and target profile hash are identical.');
    }

    result = MigrationPreparationResult(
      ok: issues.isEmpty,
      issues: issues,
      warnings: warnings,
      metadata: <String, dynamic>{
        'plan_id': plan.id,
        'status': plan.status.name,
      },
    );

    _emitPrepared(plan: plan, result: result);
    return result;
  }

  /// Executes a migration plan via the configured endpoint.
  Future<MigrationExecutionResult> execute({
    required final MigrationPlan plan,
  }) async {
    if (_endpoint != null) {
      final decisionStates = await _decisionStore.loadAllStates();
      final pauseForDecisions =
          _migrationPlanBool(plan.metadata, 'pause_for_decisions') ??
          _migrationPlanInteractionLevel(plan.metadata);
      final collectDiffs =
          _migrationPlanBool(plan.metadata, 'collect_diffs') ??
          pauseForDecisions;
      final overwrite = _migrationPlanBool(plan.metadata, 'overwrite') ?? true;
      final dryRun = _migrationPlanBool(plan.metadata, 'dry_run') ?? false;

      final executionResult = await _endpoint.executeMigrationWithOptions(
        plan: plan,
        overwrite: overwrite,
        dryRun: dryRun,
        collectDiffs: collectDiffs,
        pauseForDecisions: pauseForDecisions,
        decisionStates: decisionStates,
      );
      _emitExecuted(executionResult);
      return executionResult;
    }

    final preparation = await prepare(plan: plan);
    if (!preparation.ok) {
      return _emitFailedExecution(
        message: 'Migration preflight failed.',
        metadata: <String, dynamic>{
          'issues': preparation.issues,
          'warnings': preparation.warnings,
        },
      );
    }

    return _emitFailedExecution(
      message:
          'No migration endpoint configured. Provide MigrationEndpoint to '
          'execute migration.',
    );
  }

  /// Rolls back a previously executed migration.
  Future<MigrationExecutionResult> rollback({
    required final MigrationPlan plan,
  }) async {
    if (_endpoint == null) {
      return _emitFailedExecution(
        message:
            'No migration endpoint configured. Provide MigrationEndpoint to '
            'rollback migration.',
      );
    }

    final executionResult = await _endpoint.rollbackMigration(plan: plan);
    _emitExecuted(executionResult);
    return executionResult;
  }

  void _emitPrepared({
    required final MigrationPlan plan,
    required final MigrationPreparationResult result,
  }) {
    _observations.emit(
      type: StorageObservationType.migrationPrepared,
      namespace: StorageNamespace.settings,
      path: '',
      result: result.ok
          ? StorageOperationResult.success(message: preparationMessage(result))
          : StorageOperationResult.failure(message: preparationMessage(result)),
      metadata: <String, dynamic>{
        'plan_id': plan.id,
        'status': plan.status.name,
      },
    );
  }

  MigrationExecutionResult _emitFailedExecution({
    required final String message,
    final Map<String, dynamic> metadata = const <String, dynamic>{},
  }) {
    final executionResult = MigrationExecutionResult(
      ok: false,
      status: MigrationStatus.failed,
      message: message,
      metadata: metadata,
    );
    _emitExecuted(executionResult);
    return executionResult;
  }

  void _emitExecuted(final MigrationExecutionResult executionResult) {
    _observations.emit(
      type: StorageObservationType.migrationExecuted,
      namespace: StorageNamespace.settings,
      path: '',
      result: executionResult.ok
          ? StorageOperationResult.success(message: executionResult.message)
          : StorageOperationResult.failure(message: executionResult.message),
      metadata: <String, dynamic>{
        'plan_id': '',
        'status': executionResult.status.name,
      },
    );
  }
}

bool _migrationPlanInteractionLevel(final Map<String, dynamic> metadata) {
  final rawLevel = metadata['migration_interaction_level'];
  return rawLevel is String &&
      rawLevel.trim().toLowerCase() == SyncInteractionLevel.complex.name;
}

bool? _migrationPlanBool(
  final Map<String, dynamic> metadata,
  final String key,
) {
  final raw = metadata[key];
  if (raw == null) {
    return null;
  }
  if (raw is bool) {
    return raw;
  }
  if (raw is String) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'y') {
      return true;
    }
    if (normalized == '0' ||
        normalized == 'false' ||
        normalized == 'no' ||
        normalized == 'n') {
      return false;
    }
    return null;
  }
  if (raw is num) {
    return raw > 0;
  }
  return null;
}

/// Human-readable summary for a preparation result.
String preparationMessage(final MigrationPreparationResult result) {
  if (result.ok) {
    if (result.warnings.isNotEmpty) {
      return 'Migration prepared with warnings.';
    }
    return 'Migration preflight passed.';
  }
  if (result.issues.isEmpty) {
    return 'Migration preflight failed.';
  }
  return result.issues.join('; ');
}
