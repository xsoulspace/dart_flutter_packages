import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'storage_kernel.dart';

/// Adapter that exposes migration management as a `MigrationEndpoint`.
final class StorageProfileMigrationEndpoint implements MigrationEndpoint {
  StorageProfileMigrationEndpoint({
    required final StorageKernel sourceKernel,
    required final StorageKernel targetKernel,
    final String manifestDirectory = '.us/migrations',
    final StorageNamespace? manifestNamespace,
    final Set<String> sourcePathExcludePrefixes = const <String>{
      '.us/migrations',
    },
  }) : _manager = StorageProfileMigrationManager(
         sourceKernel: sourceKernel,
         targetKernel: targetKernel,
         manifestDirectory: manifestDirectory,
         manifestNamespace: manifestNamespace,
         sourcePathExcludePrefixes: sourcePathExcludePrefixes,
       );

  final StorageProfileMigrationManager _manager;

  @override
  Future<MigrationPreparationResult> prepareMigration({
    required final MigrationPlan plan,
  }) => _manager.prepareMigration(plan: plan);

  @override
  Future<MigrationExecutionResult> executeMigration({
    required final MigrationPlan plan,
  }) => _manager.executeMigration(plan: plan);

  /// Executes migration with explicit options.
  @override
  Future<MigrationExecutionResult> executeMigrationWithOptions({
    required final MigrationPlan plan,
    final bool overwrite = true,
    final bool dryRun = false,
    final bool collectDiffs = false,
    final bool pauseForDecisions = false,
    final Map<String, MigrationDecisionAction> decisionActions =
        const <String, MigrationDecisionAction>{},
    // Legacy alias kept for backward compatibility with migration managers that
    // still pass DecisionState values directly.
    final Map<String, DecisionState> decisionStates =
        const <String, DecisionState>{},
  }) => _manager.executeMigrationWithOptions(
    plan: plan,
    overwrite: overwrite,
    dryRun: dryRun,
    collectDiffs: collectDiffs,
    pauseForDecisions: pauseForDecisions,
    decisionActions: decisionActions,
    decisionStates: decisionStates,
  );

  @override
  Future<MigrationExecutionResult> rollbackMigration({
    required final MigrationPlan plan,
  }) => _manager.rollbackMigration(plan: plan);
}

/// Runtime that migrates data from one profile/kernel to another with checkpoints
/// and optional rollback.
final class StorageProfileMigrationManager implements MigrationEndpoint {
  StorageProfileMigrationManager({
    required final StorageKernel sourceKernel,
    required final StorageKernel targetKernel,
    this.manifestDirectory = '.us/migrations',
    this.manifestNamespace,
    this.sourcePathExcludePrefixes = const <String>{'.us/migrations'},
  }) : _sourceKernel = sourceKernel,
       _targetKernel = targetKernel,
       _managerInstanceId =
           'migration_manager_${DateTime.now().toUtc().microsecondsSinceEpoch}_${++_instanceCounter}';

  static const int _manifestSchemaVersion = 2;
  static const Duration _manifestLockTtl = Duration(minutes: 10);
  static int _instanceCounter = 0;

  final StorageKernel _sourceKernel;
  final StorageKernel _targetKernel;
  final Set<String> _activePlanLocks = <String>{};
  final String _managerInstanceId;

  /// Directory where migration manifests are stored.
  final String manifestDirectory;

  /// Namespace for manifest files. Defaults to settings namespace if not set.
  final StorageNamespace? manifestNamespace;

  /// Paths in source namespace to exclude from migration.
  final Set<String> sourcePathExcludePrefixes;

  /// Creates a migration plan manifest and performs preflight checks.
  @override
  Future<MigrationPreparationResult> prepareMigration({
    required final MigrationPlan plan,
  }) async {
    final issues = <String>[];
    final warnings = <String>[];

    if (plan.id.trim().isEmpty) {
      issues.add('Plan id is required.');
    }
    if (plan.sourceProfileHash.isEmpty || plan.targetProfileHash.isEmpty) {
      issues.add('Source and target profile hashes must be set.');
    }

    if (issues.isNotEmpty) {
      return MigrationPreparationResult(
        ok: false,
        issues: issues,
        warnings: warnings,
        metadata: <String, dynamic>{
          'source_profile': _sourceKernel.profile.name,
          'target_profile': _targetKernel.profile.name,
        },
      );
    }

    final mappings = _resolveNamespaceMappings(plan);
    final sourceNamespaces = _sourceKernel.profile.namespaces
        .map((final nsProfile) => nsProfile.namespace.value)
        .toSet();
    final targetNamespaces = _targetKernel.profile.namespaces
        .map((final nsProfile) => nsProfile.namespace.value)
        .toSet();

    if (mappings.isEmpty) {
      issues.add(
        'No compatible namespace mappings found between source and target profiles.',
      );
    }

    for (final entry in mappings.entries) {
      if (!sourceNamespaces.contains(entry.key.value)) {
        issues.add(
          'Source namespace ${entry.key.value} does not exist in source profile.',
        );
      }
      if (!targetNamespaces.contains(entry.value.value)) {
        issues.add(
          'Target namespace ${entry.value.value} does not exist in target profile.',
        );
      }
    }

    if (issues.isEmpty && plan.namespaceMappings.isEmpty) {
      warnings.add(
        'No explicit namespace mappings provided. Falling back by names.',
      );
    }

    final existingManifest = await _loadManifest(plan.id);
    if (existingManifest != null) {
      final status = MigrationStatus.values.firstWhere(
        (final value) => value.name == (existingManifest['status'] ?? ''),
        orElse: () => MigrationStatus.draft,
      );
      if (status == MigrationStatus.completed) {
        warnings.add(
          'A completed migration manifest already exists for this plan id.',
        );
      } else if (status == MigrationStatus.failed ||
          status == MigrationStatus.executing) {
        warnings.add(
          'A non-terminal migration manifest already exists for this plan id.',
        );
      }

      final existingSourceHash = existingManifest['source_profile_hash'];
      final existingTargetHash = existingManifest['target_profile_hash'];
      if (existingSourceHash != plan.sourceProfileHash ||
          existingTargetHash != plan.targetProfileHash) {
        warnings.add(
          'Existing manifest profile hashes differ from provided plan hashes.',
        );
      }
    }

    return MigrationPreparationResult(
      ok: issues.isEmpty,
      issues: issues,
      warnings: warnings,
      metadata: <String, dynamic>{
        'source_profile': _sourceKernel.profile.name,
        'target_profile': _targetKernel.profile.name,
        'namespace_mappings': mappings.map(
          (final key, final value) => MapEntry(key.value, value.value),
        ),
      },
    );
  }

  /// Executes migration with resume support.
  @override
  Future<MigrationExecutionResult> executeMigration({
    required final MigrationPlan plan,
  }) async => executeMigrationWithOptions(plan: plan);

  /// Executes migration with optional overwrite and dry-run strategy.
  @override
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
  }) async {
    final preparation = await prepareMigration(plan: plan);
    if (!preparation.ok) {
      return MigrationExecutionResult(
        ok: false,
        status: MigrationStatus.failed,
        message: preparation.issues.join('\n'),
        metadata: <String, dynamic>{
          'issues': preparation.issues,
          'warnings': preparation.warnings,
        },
      );
    }

    final lockAcquired = await _acquirePlanLock(plan.id);
    if (!lockAcquired) {
      return MigrationExecutionResult(
        ok: false,
        status: MigrationStatus.failed,
        message: 'Migration ${plan.id} is already in progress.',
        metadata: const <String, dynamic>{
          'issues': <String>['Migration lock is held by another execution.'],
        },
      );
    }

    final lockOwner = '$_managerInstanceId.${plan.id}';
    final lockAcquiredAt = DateTime.now().toUtc();

    try {
      final mappings = _resolveNamespaceMappings(plan);
      final manifest = await _loadManifest(plan.id);
      final transformConfig = _MigrationTransformConfig.fromMetadata(
        plan.metadata,
      );
      final mergedDecisionActions = <String, MigrationDecisionAction>{
        ..._manifestDecisionActions(manifest: manifest),
        ..._legacyDecisionStatesToAction(decisionStates),
        ...decisionActions,
      };
      final completedOperations = _manifestRecords(
        manifest: manifest,
        mappings: mappings,
      );
      final operations = <_MigrationOperation>[];
      for (final mapping in mappings.entries) {
        final sourceNamespace = mapping.key;
        final targetNamespace = mapping.value;

        final sourceFiles = await _collectSourceFiles(
          namespace: sourceNamespace,
          directoryPath: '.',
        );

        for (final sourcePath in sourceFiles) {
          if (_shouldSkipPath(sourcePath)) {
            continue;
          }
          final transformedPath = transformConfig.transformPath(sourcePath);
          final targetPath = transformedPath.isEmpty
              ? _normalizePath(sourcePath)
              : transformedPath;
          operations.add(
            _MigrationOperation(
              id: _migrationOperationId(
                sourceNamespace: sourceNamespace,
                sourcePath: sourcePath,
                targetNamespace: targetNamespace,
                targetPath: targetPath,
              ),
              sourceNamespace: sourceNamespace,
              targetNamespace: targetNamespace,
              sourcePath: sourcePath,
              targetPath: targetPath,
            ),
          );
        }
      }
      operations.sort(
        (final left, final right) => left.key.compareTo(right.key),
      );

      final completed = <String>{
        for (final operation in completedOperations) operation.key,
      };
      final preflight = collectDiffs ? <_MigrationOperationPreview>[] : null;
      final writtenRecords = List<_MigrationRecord>.from(completedOperations);
      final checkpointsByOperationId = <String, _MigrationCheckpoint>{
        for (final checkpoint in _manifestCheckpoints(manifest))
          checkpoint.operationId: checkpoint,
      };
      final pendingDecisionActions = <String>[];
      final issues = <String>[];
      final activeDecisionActions = <String, MigrationDecisionAction>{
        ...mergedDecisionActions,
      };
      var abortOperationId = '';

      final alreadyCompleted = completed.length;
      if (!dryRun) {
        await _persistManifest(
          planId: plan.id,
          sourceProfileHash: plan.sourceProfileHash,
          targetProfileHash: plan.targetProfileHash,
          status: MigrationStatus.executing,
          mappings: mappings,
          records: writtenRecords,
          totalOperations: operations.length,
          lockOwner: lockOwner,
          lockAcquiredAt: lockAcquiredAt,
          decisionActions: activeDecisionActions,
          checkpoints: _checkpointMapToSortedList(checkpointsByOperationId),
          paritySummary: _buildParitySummary(
            totalOperations: operations.length,
            checkpoints: checkpointsByOperationId.values,
            issues: issues,
          ),
          transformConfig: transformConfig.toJson(),
          issueDetails: issues,
        );
      }

      for (final operation in operations) {
        if (completed.contains(operation.key)) {
          continue;
        }

        final operationStartedAt = DateTime.now().toUtc();
        try {
          final sourceContent = await _sourceKernel.read(
            namespace: operation.sourceNamespace,
            path: operation.sourcePath,
          );
          if (sourceContent == null) {
            checkpointsByOperationId[operation.id] = _MigrationCheckpoint(
              id: operation.id,
              operationId: operation.id,
              sourceNamespace: operation.sourceNamespace,
              targetNamespace: operation.targetNamespace,
              sourcePath: operation.sourcePath,
              targetPath: operation.targetPath,
              status: 'source_missing',
              stable: false,
              startedAt: operationStartedAt,
              completedAt: DateTime.now().toUtc(),
              errorMessage: 'source_not_found',
            );
            if (preflight != null) {
              preflight.add(
                _MigrationOperationPreview(
                  sourceNamespace: operation.sourceNamespace,
                  targetNamespace: operation.targetNamespace,
                  operationId: operation.id,
                  sourcePath: operation.sourcePath,
                  targetPath: operation.targetPath,
                  status: 'source_missing',
                  willApply: false,
                  decisionState: DecisionState.blocked,
                  metadata: <String, dynamic>{
                    'error': 'source_not_found',
                    'target_path': operation.targetPath,
                  },
                ),
              );
            }
            issues.add(
              'Source file not found: ${operation.sourcePath} in '
              '${operation.sourceNamespace.value}.',
            );
            if (!dryRun) {
              await _persistManifest(
                planId: plan.id,
                sourceProfileHash: plan.sourceProfileHash,
                targetProfileHash: plan.targetProfileHash,
                status: MigrationStatus.executing,
                mappings: mappings,
                records: writtenRecords,
                totalOperations: operations.length,
                lockOwner: lockOwner,
                lockAcquiredAt: lockAcquiredAt,
                decisionActions: activeDecisionActions,
                checkpoints: _checkpointMapToSortedList(
                  checkpointsByOperationId,
                ),
                paritySummary: _buildParitySummary(
                  totalOperations: operations.length,
                  checkpoints: checkpointsByOperationId.values,
                  issues: issues,
                ),
                transformConfig: transformConfig.toJson(),
                issueDetails: issues,
              );
            }
            continue;
          }

          final transformResult = transformConfig.transformContent(
            sourceNamespace: operation.sourceNamespace,
            targetNamespace: operation.targetNamespace,
            sourcePath: operation.sourcePath,
            targetPath: operation.targetPath,
            sourceContent: sourceContent,
          );
          final transformedContent = transformResult.content;
          final sourceChecksum = normalizedSha256Hex(sourceContent);
          final transformedChecksum = normalizedSha256Hex(transformedContent);

          String targetContent = '';
          String targetChecksum = '';
          var targetExists = false;
          try {
            final rawTargetContent = await _targetKernel.read(
              namespace: operation.targetNamespace,
              path: operation.targetPath,
            );
            if (rawTargetContent != null) {
              targetExists = true;
              targetContent = rawTargetContent;
              targetChecksum = normalizedSha256Hex(rawTargetContent);
            }
          } catch (_) {
            targetContent = '';
            targetChecksum = '';
          }

          var status = 'create';
          var willApply = true;
          var decisionState = DecisionState.autoResolved;
          var resolvedAction = pauseForDecisions
              ? activeDecisionActions[operation.id]
              : null;
          var willAbort = false;

          if (targetExists && targetContent == transformedContent) {
            status = 'no_change';
            willApply = false;
          } else if (targetExists && overwrite) {
            status = 'overwrite';
          } else if (targetExists && !overwrite) {
            status = 'conflict';
            willApply = false;
            resolvedAction = pauseForDecisions ? resolvedAction : null;
            decisionState = resolvedAction == null
                ? DecisionState.needsUserDecision
                : _migrationDecisionStateFromAction(resolvedAction);
            if (pauseForDecisions && resolvedAction == null) {
              pendingDecisionActions.add(operation.id);
            }
            if (resolvedAction == MigrationDecisionAction.overwrite) {
              status = 'overwrite';
              willApply = true;
            } else if (resolvedAction == MigrationDecisionAction.skip) {
              status = 'skip';
            } else if (resolvedAction == MigrationDecisionAction.abort) {
              status = 'abort';
              willAbort = true;
            }
          }

          if (dryRun) {
            final metadata = <String, dynamic>{
              'source_length': sourceContent.length,
              'transformed_length': transformedContent.length,
              'target_length': targetExists ? targetContent.length : 0,
              'diff_summary': _buildDiffSummary(
                sourceContent: transformedContent,
                targetContent: targetContent,
              ),
              'source_preview': _truncateContent(sourceContent),
              'transformed_preview': _truncateContent(transformedContent),
              'target_preview': _truncateContent(targetContent),
              'source_checksum': sourceChecksum,
              'transformed_checksum': transformedChecksum,
              if (targetChecksum.isNotEmpty) 'target_checksum': targetChecksum,
              'transform_steps': transformResult.steps,
            };
            if (resolvedAction != null) {
              metadata['decision_action'] = resolvedAction.name;
            }

            if (preflight != null) {
              preflight.add(
                _MigrationOperationPreview(
                  sourceNamespace: operation.sourceNamespace,
                  targetNamespace: operation.targetNamespace,
                  operationId: operation.id,
                  sourcePath: operation.sourcePath,
                  targetPath: operation.targetPath,
                  status: status,
                  willApply: willApply,
                  decisionState: decisionState,
                  metadata: metadata,
                ),
              );
            }

            checkpointsByOperationId[operation.id] = _MigrationCheckpoint(
              id: operation.id,
              operationId: operation.id,
              sourceNamespace: operation.sourceNamespace,
              targetNamespace: operation.targetNamespace,
              sourcePath: operation.sourcePath,
              targetPath: operation.targetPath,
              status: status,
              stable: false,
              sourceChecksum: sourceChecksum,
              transformedChecksum: transformedChecksum,
              targetChecksum: targetChecksum.isEmpty ? null : targetChecksum,
              checksumVerified: targetChecksum.isEmpty
                  ? null
                  : targetChecksum == transformedChecksum,
              transformSteps: transformResult.steps,
              startedAt: operationStartedAt,
              completedAt: DateTime.now().toUtc(),
            );
            completed.add(operation.key);
            continue;
          }

          if (!willApply) {
            if (willAbort) {
              abortOperationId = operation.id;
              activeDecisionActions[operation.id] =
                  MigrationDecisionAction.abort;
            }
            if (preflight != null) {
              preflight.add(
                _MigrationOperationPreview(
                  sourceNamespace: operation.sourceNamespace,
                  targetNamespace: operation.targetNamespace,
                  operationId: operation.id,
                  sourcePath: operation.sourcePath,
                  targetPath: operation.targetPath,
                  status: status,
                  willApply: false,
                  decisionState: decisionState,
                  metadata: <String, dynamic>{
                    'source_length': sourceContent.length,
                    'transformed_length': transformedContent.length,
                    'target_length': targetExists ? targetContent.length : 0,
                    'diff_summary': _buildDiffSummary(
                      sourceContent: transformedContent,
                      targetContent: targetContent,
                    ),
                    'source_preview': _truncateContent(sourceContent),
                    'transformed_preview': _truncateContent(transformedContent),
                    'target_preview': _truncateContent(targetContent),
                    'source_checksum': sourceChecksum,
                    'transformed_checksum': transformedChecksum,
                    if (targetChecksum.isNotEmpty)
                      'target_checksum': targetChecksum,
                    'transform_steps': transformResult.steps,
                    if (resolvedAction != null)
                      'decision_action': resolvedAction.name,
                  },
                ),
              );
            }
            final checkpointStatus = switch (status) {
              'no_change' => 'no_change',
              'skip' => 'skipped',
              'abort' => 'aborted',
              'conflict' =>
                pauseForDecisions && resolvedAction == null
                    ? 'awaiting_decision'
                    : 'conflict',
              _ => status,
            };
            checkpointsByOperationId[operation.id] = _MigrationCheckpoint(
              id: operation.id,
              operationId: operation.id,
              sourceNamespace: operation.sourceNamespace,
              targetNamespace: operation.targetNamespace,
              sourcePath: operation.sourcePath,
              targetPath: operation.targetPath,
              status: checkpointStatus,
              stable:
                  checkpointStatus == 'no_change' ||
                  checkpointStatus == 'skipped',
              sourceChecksum: sourceChecksum,
              transformedChecksum: transformedChecksum,
              targetChecksum: targetChecksum.isEmpty ? null : targetChecksum,
              checksumVerified: targetChecksum.isEmpty
                  ? null
                  : targetChecksum == transformedChecksum,
              transformSteps: transformResult.steps,
              startedAt: operationStartedAt,
              completedAt: DateTime.now().toUtc(),
              errorMessage: checkpointStatus == 'awaiting_decision'
                  ? 'decision_required'
                  : null,
            );
            completed.add(operation.key);
            if (!dryRun) {
              await _persistManifest(
                planId: plan.id,
                sourceProfileHash: plan.sourceProfileHash,
                targetProfileHash: plan.targetProfileHash,
                status: MigrationStatus.executing,
                mappings: mappings,
                records: writtenRecords,
                totalOperations: operations.length,
                lockOwner: lockOwner,
                lockAcquiredAt: lockAcquiredAt,
                decisionActions: activeDecisionActions,
                checkpoints: _checkpointMapToSortedList(
                  checkpointsByOperationId,
                ),
                paritySummary: _buildParitySummary(
                  totalOperations: operations.length,
                  checkpoints: checkpointsByOperationId.values,
                  issues: issues,
                ),
                transformConfig: transformConfig.toJson(),
                issueDetails: issues,
              );
            }
            if (willAbort) {
              break;
            }
            continue;
          }

          await _targetKernel.write(
            namespace: operation.targetNamespace,
            path: operation.targetPath,
            content: transformedContent,
            message: 'Migration ${plan.id}',
          );
          final writtenTarget = await _targetKernel.read(
            namespace: operation.targetNamespace,
            path: operation.targetPath,
          );
          final verifiedTargetChecksum = writtenTarget == null
              ? ''
              : normalizedSha256Hex(writtenTarget);
          final checksumMatched =
              verifiedTargetChecksum.isNotEmpty &&
              verifiedTargetChecksum == transformedChecksum;
          if (!checksumMatched) {
            issues.add(
              'Checksum verification failed for '
              '${operation.targetNamespace.value}:${operation.targetPath}.',
            );
          }
          completed.add(operation.key);
          final newRecord = _MigrationRecord(
            sourceNamespace: operation.sourceNamespace,
            sourcePath: operation.sourcePath,
            targetNamespace: operation.targetNamespace,
            targetPath: operation.targetPath,
            operationId: operation.id,
          );
          writtenRecords.add(newRecord);
          if (pauseForDecisions) {
            activeDecisionActions[operation.id] =
                MigrationDecisionAction.overwrite;
          }
          checkpointsByOperationId[operation.id] = _MigrationCheckpoint(
            id: operation.id,
            operationId: operation.id,
            sourceNamespace: operation.sourceNamespace,
            targetNamespace: operation.targetNamespace,
            sourcePath: operation.sourcePath,
            targetPath: operation.targetPath,
            status: 'applied',
            stable: checksumMatched,
            sourceChecksum: sourceChecksum,
            transformedChecksum: transformedChecksum,
            targetChecksum: verifiedTargetChecksum.isEmpty
                ? null
                : verifiedTargetChecksum,
            checksumVerified: checksumMatched,
            spotReadVerified: checksumMatched,
            transformSteps: transformResult.steps,
            startedAt: operationStartedAt,
            completedAt: DateTime.now().toUtc(),
            errorMessage: checksumMatched ? null : 'checksum_mismatch',
          );
          await _persistManifest(
            planId: plan.id,
            sourceProfileHash: plan.sourceProfileHash,
            targetProfileHash: plan.targetProfileHash,
            status: MigrationStatus.executing,
            mappings: mappings,
            records: writtenRecords,
            totalOperations: operations.length,
            lockOwner: lockOwner,
            lockAcquiredAt: lockAcquiredAt,
            decisionActions: activeDecisionActions,
            checkpoints: _checkpointMapToSortedList(checkpointsByOperationId),
            paritySummary: _buildParitySummary(
              totalOperations: operations.length,
              checkpoints: checkpointsByOperationId.values,
              issues: issues,
            ),
            transformConfig: transformConfig.toJson(),
            issueDetails: issues,
          );
        } catch (error) {
          issues.add(error.toString());
          checkpointsByOperationId[operation.id] = _MigrationCheckpoint(
            id: operation.id,
            operationId: operation.id,
            sourceNamespace: operation.sourceNamespace,
            targetNamespace: operation.targetNamespace,
            sourcePath: operation.sourcePath,
            targetPath: operation.targetPath,
            status: 'failed',
            stable: false,
            startedAt: operationStartedAt,
            completedAt: DateTime.now().toUtc(),
            errorMessage: error.toString(),
          );
          if (!dryRun) {
            await _persistManifest(
              planId: plan.id,
              sourceProfileHash: plan.sourceProfileHash,
              targetProfileHash: plan.targetProfileHash,
              status: MigrationStatus.executing,
              mappings: mappings,
              records: writtenRecords,
              totalOperations: operations.length,
              lockOwner: lockOwner,
              lockAcquiredAt: lockAcquiredAt,
              decisionActions: activeDecisionActions,
              checkpoints: _checkpointMapToSortedList(checkpointsByOperationId),
              paritySummary: _buildParitySummary(
                totalOperations: operations.length,
                checkpoints: checkpointsByOperationId.values,
                issues: issues,
              ),
              transformConfig: transformConfig.toJson(),
              issueDetails: issues,
            );
          }
        }
      }

      final paritySummary = _buildParitySummary(
        totalOperations: operations.length,
        checkpoints: checkpointsByOperationId.values,
        issues: issues,
      );

      if (!dryRun && pauseForDecisions && pendingDecisionActions.isNotEmpty) {
        await _persistManifest(
          planId: plan.id,
          sourceProfileHash: plan.sourceProfileHash,
          targetProfileHash: plan.targetProfileHash,
          status: MigrationStatus.prepared,
          mappings: mappings,
          records: writtenRecords,
          totalOperations: operations.length,
          decisionActions: activeDecisionActions,
          checkpoints: _checkpointMapToSortedList(checkpointsByOperationId),
          paritySummary: paritySummary,
          transformConfig: transformConfig.toJson(),
          issueDetails: issues,
        );

        return MigrationExecutionResult(
          ok: false,
          status: MigrationStatus.prepared,
          message:
              'Migration paused. User decisions are required for '
              '${pendingDecisionActions.length} conflict(s).',
          metadata: <String, dynamic>{
            'operations_total': operations.length,
            'operations_completed': completed.length,
            'already_completed': alreadyCompleted,
            'issues': issues,
            'pause_for_decisions': true,
            'parity_summary': paritySummary,
            'checkpoint_ledger': <Map<String, dynamic>>[
              for (final checkpoint in _checkpointMapToSortedList(
                checkpointsByOperationId,
              ))
                checkpoint.toJson(),
            ],
            if (preflight != null)
              'preflight_preview': <Map<String, dynamic>>[
                for (final item in preflight) item.toJson(),
              ],
            'pending_decisions': <Map<String, dynamic>>[
              for (final operation in operations)
                if (pendingDecisionActions.contains(operation.id))
                  <String, dynamic>{
                    'operation_id': operation.id,
                    'source_namespace': operation.sourceNamespace.value,
                    'target_namespace': operation.targetNamespace.value,
                    'source_path': operation.sourcePath,
                    'target_path': operation.targetPath,
                  },
            ],
            'decision_actions': <String, String>{
              for (final item in activeDecisionActions.entries)
                item.key: item.value.name,
            },
          },
        );
      }

      if (abortOperationId.isNotEmpty) {
        await _persistManifest(
          planId: plan.id,
          sourceProfileHash: plan.sourceProfileHash,
          targetProfileHash: plan.targetProfileHash,
          status: MigrationStatus.failed,
          mappings: mappings,
          records: writtenRecords,
          totalOperations: operations.length,
          decisionActions: activeDecisionActions,
          checkpoints: _checkpointMapToSortedList(checkpointsByOperationId),
          paritySummary: paritySummary,
          transformConfig: transformConfig.toJson(),
          issueDetails: issues,
        );

        return MigrationExecutionResult(
          ok: false,
          status: MigrationStatus.failed,
          message: 'Migration aborted by user for operation $abortOperationId.',
          metadata: <String, dynamic>{
            'abort_operation_id': abortOperationId,
            'operations_total': operations.length,
            'operations_completed': completed.length,
            'already_completed': alreadyCompleted,
            'issues': issues,
            'pause_for_decisions': true,
            'parity_summary': paritySummary,
            'checkpoint_ledger': <Map<String, dynamic>>[
              for (final checkpoint in _checkpointMapToSortedList(
                checkpointsByOperationId,
              ))
                checkpoint.toJson(),
            ],
            'decision_actions': <String, String>{
              for (final item in activeDecisionActions.entries)
                item.key: item.value.name,
            },
          },
        );
      }

      if (dryRun) {
        return MigrationExecutionResult(
          ok: issues.isEmpty,
          status: MigrationStatus.prepared,
          message: issues.isEmpty
              ? 'Dry-run completed. ${operations.length} operations evaluated.'
              : 'Dry-run completed with ${issues.length} potential issue(s).',
          metadata: <String, dynamic>{
            'operations_total': operations.length,
            'operations_completed': completed.length,
            'already_completed': alreadyCompleted,
            'issues': issues,
            'dry_run': true,
            'parity_summary': paritySummary,
            'checkpoint_ledger': <Map<String, dynamic>>[
              for (final checkpoint in _checkpointMapToSortedList(
                checkpointsByOperationId,
              ))
                checkpoint.toJson(),
            ],
            if (preflight != null)
              'preflight_preview': <Map<String, dynamic>>[
                for (final item in preflight) item.toJson(),
              ],
          },
        );
      }

      final finalStatus = issues.isEmpty
          ? MigrationStatus.completed
          : MigrationStatus.failed;
      await _persistManifest(
        planId: plan.id,
        sourceProfileHash: plan.sourceProfileHash,
        targetProfileHash: plan.targetProfileHash,
        status: finalStatus,
        mappings: mappings,
        records: writtenRecords,
        totalOperations: operations.length,
        decisionActions: activeDecisionActions,
        checkpoints: _checkpointMapToSortedList(checkpointsByOperationId),
        paritySummary: paritySummary,
        transformConfig: transformConfig.toJson(),
        issueDetails: issues,
      );

      return MigrationExecutionResult(
        ok: issues.isEmpty,
        status: finalStatus,
        message: issues.isEmpty
            ? 'Migration executed. ${completed.length}/${operations.length} operations copied.'
            : 'Migration finished with ${issues.length} errors. ${completed.length}/${operations.length} processed.',
        metadata: <String, dynamic>{
          'operations_total': operations.length,
          'operations_completed': completed.length,
          'issues': issues,
          'parity_summary': paritySummary,
          'checkpoint_ledger': <Map<String, dynamic>>[
            for (final checkpoint in _checkpointMapToSortedList(
              checkpointsByOperationId,
            ))
              checkpoint.toJson(),
          ],
        },
      );
    } finally {
      _releasePlanLock(plan.id);
    }
  }

  /// Rolls back files created by a previously executed migration plan.
  @override
  Future<MigrationExecutionResult> rollbackMigration({
    required final MigrationPlan plan,
  }) async => rollbackMigrationById(
    planId: plan.id,
    rollbackToCheckpointId: plan.metadata['rollback_to_checkpoint_id']
        ?.toString(),
  );

  /// Rolls back files created by a previously executed migration plan.
  Future<MigrationExecutionResult> rollbackMigrationById({
    required final String planId,
    final String? rollbackToCheckpointId,
  }) async {
    final lockAcquired = await _acquirePlanLock(planId);
    if (!lockAcquired) {
      return MigrationExecutionResult(
        ok: false,
        status: MigrationStatus.failed,
        message: 'Migration $planId is already in progress.',
        metadata: const <String, dynamic>{
          'issues': <String>['Migration lock is held by another execution.'],
        },
      );
    }

    try {
      final manifest = await _loadManifest(planId);
      if (manifest == null) {
        return MigrationExecutionResult(
          ok: false,
          status: MigrationStatus.failed,
          message: 'No migration manifest found for plan: $planId',
        );
      }

      final mappings = <StorageNamespace, StorageNamespace>{};
      final mappingData = manifest['namespace_mappings'];
      if (mappingData is Map) {
        for (final entry in mappingData.entries) {
          final sourceNamespace = StorageNamespace.fromJson(entry.key);
          final targetNamespace = StorageNamespace.fromJson(entry.value);
          mappings[sourceNamespace] = targetNamespace;
        }
      }

      final writtenRecords = _manifestRecords(
        manifest: manifest,
        mappings: mappings,
      );
      final checkpoints = _manifestCheckpoints(manifest);
      final rollbackRecords = _recordsForRollback(
        records: writtenRecords,
        checkpoints: checkpoints,
        rollbackToCheckpointId: rollbackToCheckpointId,
      );
      if (rollbackToCheckpointId != null && rollbackRecords == null) {
        return MigrationExecutionResult(
          ok: false,
          status: MigrationStatus.failed,
          message:
              'Checkpoint $rollbackToCheckpointId is not available for migration $planId.',
          metadata: const <String, dynamic>{
            'issues': <String>['rollback_checkpoint_not_found'],
          },
        );
      }
      final recordsToRemove = rollbackRecords ?? writtenRecords;

      var removed = 0;
      final issues = <String>[];
      for (final record in recordsToRemove.reversed) {
        try {
          await _targetKernel.delete(
            namespace: record.targetNamespace,
            path: record.targetPath,
          );
          removed++;
        } catch (error) {
          issues.add(error.toString());
        }
      }
      if (rollbackToCheckpointId == null) {
        await _deleteManifest(planId);
      } else {
        final checkpointIndex = checkpoints.indexWhere(
          (final item) => item.id == rollbackToCheckpointId,
        );
        final retainedCheckpoints = checkpoints
            .take(checkpointIndex + 1)
            .toList(growable: false);
        final retainedOperationIds = retainedCheckpoints
            .map((final item) => item.operationId)
            .toSet();

        final retainedRecords = writtenRecords
            .where(
              (final record) =>
                  record.operationId != null &&
                  retainedOperationIds.contains(record.operationId),
            )
            .toList(growable: false);

        await _persistManifest(
          planId: planId,
          sourceProfileHash: manifest['source_profile_hash']?.toString() ?? '',
          targetProfileHash: manifest['target_profile_hash']?.toString() ?? '',
          status: issues.isEmpty
              ? MigrationStatus.prepared
              : MigrationStatus.failed,
          mappings: mappings,
          records: retainedRecords,
          totalOperations: (manifest['operations_total'] as num?)?.toInt() ?? 0,
          checkpoints: retainedCheckpoints,
          paritySummary: _buildParitySummary(
            totalOperations:
                (manifest['operations_total'] as num?)?.toInt() ?? 0,
            checkpoints: retainedCheckpoints,
            issues: issues,
          ),
          transformConfig: manifest['transform_config'] is Map
              ? Map<String, dynamic>.from(
                  manifest['transform_config'] as Map<dynamic, dynamic>,
                )
              : const <String, dynamic>{},
          issueDetails: issues,
        );
      }

      return MigrationExecutionResult(
        ok: issues.isEmpty,
        status: issues.isEmpty
            ? MigrationStatus.rolledBack
            : MigrationStatus.failed,
        message: issues.isEmpty
            ? rollbackToCheckpointId == null
                  ? 'Rollback removed $removed file(s).'
                  : 'Rollback to checkpoint $rollbackToCheckpointId removed '
                        '$removed file(s).'
            : 'Rollback completed with ${issues.length} error(s).',
        metadata: <String, dynamic>{
          'removed': removed,
          'issues': issues,
          if (rollbackToCheckpointId != null)
            'rollback_to_checkpoint_id': rollbackToCheckpointId,
        },
      );
    } finally {
      _releasePlanLock(planId);
    }
  }

  void _releasePlanLock(final String planId) => _activePlanLocks.remove(planId);

  Future<bool> _acquirePlanLock(final String planId) async {
    if (_activePlanLocks.contains(planId)) {
      return false;
    }

    final manifest = await _loadManifest(planId);
    if (manifest != null) {
      final status = _migrationStatusFromManifest(manifest);
      if (status == MigrationStatus.executing) {
        final lock = _manifestLockFromManifest(manifest);
        final lockTime =
            lock?.acquiredAt ?? _parseDateTime(manifest['updated_at']);
        if (!_isPlanLockStale(lockTime)) {
          return false;
        }
      }
    }

    _activePlanLocks.add(planId);
    return true;
  }

  bool _isPlanLockStale(final DateTime? acquiredAt) {
    if (acquiredAt == null) {
      return true;
    }
    final now = DateTime.now().toUtc();
    return now.difference(acquiredAt) > _manifestLockTtl;
  }

  MigrationStatus _migrationStatusFromManifest(
    final Map<String, dynamic> manifest,
  ) => MigrationStatus.values.firstWhere(
    (final value) => value.name == (manifest['status'] ?? ''),
    orElse: () => MigrationStatus.draft,
  );

  _MigrationLockInfo? _manifestLockFromManifest(
    final Map<String, dynamic> manifest,
  ) {
    final rawLock = manifest['migration_lock'];
    if (rawLock is! Map) {
      return null;
    }

    return _MigrationLockInfo(
      owner: rawLock['owner']?.toString(),
      acquiredAt: _parseDateTime(rawLock['acquired_at']),
    );
  }

  DateTime? _parseDateTime(final Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  Future<List<String>> _collectSourceFiles({
    required final StorageNamespace namespace,
    required final String directoryPath,
  }) async {
    final normalizedDirectory = _normalizePath(directoryPath);
    final entries = await _sourceKernel.list(
      namespace: namespace,
      directoryPath: normalizedDirectory,
    );
    final files = <String>[];

    for (final entry in entries) {
      final normalizedPath = _joinPath(normalizedDirectory, entry.name);
      if (entry.isDirectory) {
        files.addAll(
          await _collectSourceFiles(
            namespace: namespace,
            directoryPath: normalizedPath,
          ),
        );
        continue;
      }
      files.add(normalizedPath);
    }

    return files;
  }

  Map<StorageNamespace, StorageNamespace> _resolveNamespaceMappings(
    final MigrationPlan plan,
  ) {
    final mappings = <StorageNamespace, StorageNamespace>{};
    final sourceNamespaces = <String, StorageNamespace>{
      for (final namespaceProfile in _sourceKernel.profile.namespaces)
        namespaceProfile.namespace.value: namespaceProfile.namespace,
    };
    final targetNamespaces = <String, StorageNamespace>{
      for (final namespaceProfile in _targetKernel.profile.namespaces)
        namespaceProfile.namespace.value: namespaceProfile.namespace,
    };

    if (plan.namespaceMappings.isEmpty) {
      for (final sourceNamespace in sourceNamespaces.keys) {
        final targetNamespace = targetNamespaces[sourceNamespace];
        if (targetNamespace != null) {
          mappings[sourceNamespaces[sourceNamespace]!] = targetNamespace;
        }
      }
      return mappings;
    }

    for (final entry in plan.namespaceMappings.entries) {
      final sourceNamespace = sourceNamespaces[entry.key];
      final targetNamespace = targetNamespaces[entry.value];
      if (sourceNamespace == null || targetNamespace == null) {
        continue;
      }
      mappings[sourceNamespace] = targetNamespace;
    }
    return mappings;
  }

  bool _shouldSkipPath(final String path) {
    final normalizedPath = _normalizePath(path);
    for (final excludedRaw in sourcePathExcludePrefixes) {
      final excluded = _normalizePath(excludedRaw);
      if (excluded.isEmpty) {
        continue;
      }
      if (normalizedPath == excluded ||
          normalizedPath.startsWith('$excluded/')) {
        return true;
      }
    }
    return false;
  }

  StorageNamespace _manifestNamespace() =>
      manifestNamespace ??
      _targetKernel.profile.namespaces
          .map((final namespaceProfile) => namespaceProfile.namespace)
          .firstWhere(
            (final namespace) => namespace == StorageNamespace.settings,
            orElse: () => _targetKernel.profile.namespaces.first.namespace,
          );

  String _manifestPath(final String planId) =>
      '$manifestDirectory/${_sanitizeManifestFileName(planId)}.json';

  Future<Map<String, dynamic>?> _loadManifest(final String planId) async {
    final raw = await _targetKernel.read(
      namespace: _manifestNamespace(),
      path: _manifestPath(planId),
    );
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
  }

  List<_MigrationRecord> _manifestRecords({
    required final Map<String, dynamic>? manifest,
    required final Map<StorageNamespace, StorageNamespace> mappings,
  }) {
    final rawWritten = manifest?['written'];
    if (rawWritten is! List) {
      return const <_MigrationRecord>[];
    }

    final records = <_MigrationRecord>[];
    for (final item in rawWritten) {
      if (item is Map) {
        final parsed = _MigrationRecord.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (parsed != null) {
          records.add(parsed);
        }
      } else if (item is String) {
        final separatorIndex = item.indexOf(':');
        if (separatorIndex < 0) {
          continue;
        }
        final sourceNamespace = StorageNamespace.fromJson(
          item.substring(0, separatorIndex),
        );
        final sourcePath = item.substring(separatorIndex + 1);
        final targetNamespace = mappings[sourceNamespace] ?? sourceNamespace;
        records.add(
          _MigrationRecord(
            sourceNamespace: sourceNamespace,
            sourcePath: sourcePath,
            targetNamespace: targetNamespace,
            targetPath: sourcePath,
          ),
        );
      }
    }
    return records;
  }

  List<_MigrationCheckpoint> _manifestCheckpoints(
    final Map<String, dynamic>? manifest,
  ) {
    final rawCheckpoints = manifest?['checkpoints'];
    if (rawCheckpoints is! List) {
      return const <_MigrationCheckpoint>[];
    }

    final checkpoints = <_MigrationCheckpoint>[];
    for (final item in rawCheckpoints) {
      if (item is! Map) {
        continue;
      }
      final parsed = _MigrationCheckpoint.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (parsed != null) {
        checkpoints.add(parsed);
      }
    }
    checkpoints.sort(
      (final left, final right) =>
          '${left.sourceNamespace.value}:${left.sourcePath}'.compareTo(
            '${right.sourceNamespace.value}:${right.sourcePath}',
          ),
    );
    return checkpoints;
  }

  List<_MigrationCheckpoint> _checkpointMapToSortedList(
    final Map<String, _MigrationCheckpoint> checkpointsByOperationId,
  ) {
    final checkpoints = checkpointsByOperationId.values.toList(growable: false);
    checkpoints.sort(
      (final left, final right) =>
          '${left.sourceNamespace.value}:${left.sourcePath}'.compareTo(
            '${right.sourceNamespace.value}:${right.sourcePath}',
          ),
    );
    return checkpoints;
  }

  Map<String, dynamic> _buildParitySummary({
    required final int totalOperations,
    required final Iterable<_MigrationCheckpoint> checkpoints,
    required final List<String> issues,
  }) {
    var applied = 0;
    var unchanged = 0;
    var skipped = 0;
    var awaitingDecision = 0;
    var failed = 0;
    var checksumCompared = 0;
    var checksumMatched = 0;
    var spotReadVerified = 0;
    var spotReadFailed = 0;
    _MigrationCheckpoint? lastStableCheckpoint;

    for (final checkpoint in checkpoints) {
      if (checkpoint.status == 'applied' || checkpoint.status == 'overwrite') {
        applied++;
      } else if (checkpoint.status == 'no_change') {
        unchanged++;
      } else if (checkpoint.status == 'skipped' ||
          checkpoint.status == 'skip') {
        skipped++;
      } else if (checkpoint.status == 'awaiting_decision') {
        awaitingDecision++;
      } else if (checkpoint.status == 'failed' ||
          checkpoint.status == 'source_missing' ||
          checkpoint.status == 'aborted') {
        failed++;
      }

      if (checkpoint.checksumVerified != null) {
        checksumCompared++;
        if (checkpoint.checksumVerified == true) {
          checksumMatched++;
        }
      }

      if (checkpoint.spotReadVerified != null) {
        if (checkpoint.spotReadVerified == true) {
          spotReadVerified++;
        } else {
          spotReadFailed++;
        }
      }

      if (checkpoint.stable) {
        lastStableCheckpoint = checkpoint;
      }
    }

    final processed = applied + unchanged + skipped + awaitingDecision + failed;
    final pendingOperations = processed >= totalOperations
        ? 0
        : totalOperations - processed;
    return <String, dynamic>{
      'count_parity': <String, dynamic>{
        'source_operations': totalOperations,
        'processed_operations': processed,
        'pending_operations': pendingOperations,
        'is_balanced': processed <= totalOperations,
      },
      'checksum_parity': <String, dynamic>{
        'compared': checksumCompared,
        'matched': checksumMatched,
        'mismatched': checksumCompared - checksumMatched,
      },
      'spot_read_verification': <String, dynamic>{
        'verified': spotReadVerified,
        'failed': spotReadFailed,
      },
      'status_counts': <String, dynamic>{
        'applied': applied,
        'unchanged': unchanged,
        'skipped': skipped,
        'awaiting_decision': awaitingDecision,
        'failed': failed,
      },
      if (lastStableCheckpoint != null)
        'last_stable_checkpoint_id': lastStableCheckpoint.id,
      if (issues.isNotEmpty) 'errors': issues,
    };
  }

  List<_MigrationRecord>? _recordsForRollback({
    required final List<_MigrationRecord> records,
    required final List<_MigrationCheckpoint> checkpoints,
    required final String? rollbackToCheckpointId,
  }) {
    if (rollbackToCheckpointId == null) {
      return null;
    }
    final checkpointIndex = checkpoints.indexWhere(
      (final item) => item.id == rollbackToCheckpointId,
    );
    if (checkpointIndex < 0) {
      return null;
    }
    if (records.any((final record) => record.operationId == null)) {
      return null;
    }

    final retainedOperationIds = checkpoints
        .take(checkpointIndex + 1)
        .map((final item) => item.operationId)
        .toSet();
    return records
        .where(
          (final record) =>
              record.operationId != null &&
              !retainedOperationIds.contains(record.operationId),
        )
        .toList(growable: false);
  }

  Map<String, MigrationDecisionAction> _manifestDecisionActions({
    required final Map<String, dynamic>? manifest,
  }) {
    final rawDecisionStates = manifest?['decision_states'];
    final rawDecisionActions = manifest?['decision_actions'];
    final rawDecisionPayload = rawDecisionActions ?? rawDecisionStates;

    if (rawDecisionPayload is! Map) {
      return <String, MigrationDecisionAction>{};
    }

    final result = <String, MigrationDecisionAction>{};
    if (rawDecisionStates is Map) {
      for (final entry in rawDecisionStates.entries) {
        final stateName = entry.value?.toString();
        if (stateName == null || stateName.isEmpty) {
          continue;
        }
        final legacyState = DecisionState.values.firstWhere(
          (final item) => item.name == stateName,
          orElse: () => DecisionState.autoResolved,
        );
        final action = _migrationDecisionFromLegacyState(legacyState);
        if (action != null) {
          result[entry.key.toString()] = action;
        }
      }
    }

    for (final entry in rawDecisionPayload.entries) {
      final key = entry.key?.toString();
      final action = migrationDecisionActionFromString(entry.value);
      if (key == null || key.isEmpty || action == null) {
        continue;
      }
      result[key] = action;
    }

    return result;
  }

  Map<String, MigrationDecisionAction> _legacyDecisionStatesToAction(
    final Map<String, DecisionState> states,
  ) => <String, MigrationDecisionAction>{
    for (final entry in states.entries)
      if (_migrationDecisionFromLegacyState(entry.value) != null)
        entry.key: _migrationDecisionFromLegacyState(entry.value)!,
  };

  MigrationDecisionAction? _migrationDecisionFromLegacyState(
    final DecisionState state,
  ) => switch (state) {
    DecisionState.autoResolved => MigrationDecisionAction.overwrite,
    DecisionState.blocked => MigrationDecisionAction.skip,
    DecisionState.needsUserDecision => null,
  };

  DecisionState _migrationDecisionStateFromAction(
    final MigrationDecisionAction action,
  ) => switch (action) {
    MigrationDecisionAction.overwrite => DecisionState.autoResolved,
    MigrationDecisionAction.skip => DecisionState.blocked,
    MigrationDecisionAction.abort => DecisionState.blocked,
  };

  Future<void> _persistManifest({
    required final String planId,
    required final String sourceProfileHash,
    required final String targetProfileHash,
    required final MigrationStatus status,
    required final Map<StorageNamespace, StorageNamespace> mappings,
    required final List<_MigrationRecord> records,
    final int totalOperations = 0,
    final String? lockOwner,
    final DateTime? lockAcquiredAt,
    final Map<String, MigrationDecisionAction>? decisionActions,
    final List<_MigrationCheckpoint>? checkpoints,
    final Map<String, dynamic>? paritySummary,
    final Map<String, dynamic>? transformConfig,
    final List<String>? issueDetails,
  }) async {
    final payload = <String, dynamic>{
      'schema_version': _manifestSchemaVersion,
      'plan_id': planId,
      'status': status.name,
      'source_profile_hash': sourceProfileHash,
      'target_profile_hash': targetProfileHash,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'namespace_mappings': <String, String>{
        for (final mapping in mappings.entries)
          mapping.key.value: mapping.value.value,
      },
      'written': <Map<String, dynamic>>[
        for (final record in records) record.toJson(),
      ],
      'operations_total': totalOperations,
      'written_count': records.length,
      if (checkpoints != null)
        'checkpoints': <Map<String, dynamic>>[
          for (final checkpoint in checkpoints) checkpoint.toJson(),
        ],
      if (paritySummary != null) 'parity_summary': paritySummary,
      if (transformConfig != null) 'transform_config': transformConfig,
      if (issueDetails != null) 'issues': issueDetails,
      if (decisionActions != null)
        'decision_actions': <String, String>{
          for (final item in decisionActions.entries) item.key: item.value.name,
        },
      if (decisionActions != null)
        'decision_states': <String, String>{
          for (final item in decisionActions.entries) item.key: item.value.name,
        },
    };
    if (status == MigrationStatus.executing) {
      payload['migration_lock'] = <String, dynamic>{
        'owner': lockOwner ?? _managerInstanceId,
        'acquired_at': (lockAcquiredAt ?? DateTime.now().toUtc())
            .toIso8601String(),
      };
    }

    await _targetKernel.write(
      namespace: _manifestNamespace(),
      path: _manifestPath(planId),
      content: jsonEncode(payload),
      message: 'Persist migration manifest for $planId',
    );
  }

  Future<void> _deleteManifest(final String planId) async {
    try {
      await _targetKernel.delete(
        namespace: _manifestNamespace(),
        path: _manifestPath(planId),
      );
    } catch (_) {
      // Ignore manifest delete failures during rollback.
    }
  }

  String _normalizePath(final String path) => path
      .replaceAll(r'\', '/')
      .replaceAll(RegExp('/+'), '/')
      .replaceAll(RegExp('^/+'), '')
      .replaceAll(RegExp(r'/+$'), '');

  String _joinPath(final String base, final String segment) {
    final normalizedBase = _normalizePath(base);
    if (normalizedBase.isEmpty || normalizedBase == '.') {
      return _normalizePath(segment);
    }
    return _normalizePath('$normalizedBase/$segment');
  }

  String _sanitizeManifestFileName(final String value) => value
      .replaceAll(RegExp(r'[/\\]'), '_')
      .replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');

  String _migrationOperationId({
    required final StorageNamespace sourceNamespace,
    required final String sourcePath,
    required final StorageNamespace targetNamespace,
    required final String targetPath,
  }) => base64Url.encode(
    utf8.encode(
      jsonEncode(<String, String>{
        's': sourceNamespace.value,
        'sp': sourcePath,
        't': targetNamespace.value,
        'tp': targetPath,
      }),
    ),
  );
}

@immutable
final class _MigrationOperation {
  const _MigrationOperation({
    required this.id,
    required this.sourceNamespace,
    required this.targetNamespace,
    required this.sourcePath,
    required this.targetPath,
  });

  final String id;
  final StorageNamespace sourceNamespace;
  final StorageNamespace targetNamespace;
  final String sourcePath;
  final String targetPath;

  String get key => '${sourceNamespace.value}:$sourcePath';
}

@immutable
final class _MigrationOperationPreview {
  const _MigrationOperationPreview({
    required this.operationId,
    required this.sourceNamespace,
    required this.targetNamespace,
    required this.sourcePath,
    required this.targetPath,
    required this.status,
    required this.willApply,
    required this.decisionState,
    this.metadata = const <String, dynamic>{},
  });

  final StorageNamespace sourceNamespace;
  final StorageNamespace targetNamespace;
  final String sourcePath;
  final String targetPath;
  final String operationId;
  final String status;
  final bool willApply;
  final DecisionState decisionState;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'operation_id': operationId,
    'source_namespace': sourceNamespace.value,
    'target_namespace': targetNamespace.value,
    'source_path': sourcePath,
    'target_path': targetPath,
    'status': status,
    'will_apply': willApply,
    'decision_state': decisionState.name,
    'metadata': metadata,
  };
}

String _truncateContent(final String content) {
  const maxLength = 220;
  if (content.length <= maxLength) {
    return content;
  }
  return '${content.substring(0, maxLength)}...';
}

String _buildDiffSummary({
  required final String sourceContent,
  required final String targetContent,
}) {
  if (targetContent.isEmpty) {
    return 'Target file missing.';
  }
  if (sourceContent == targetContent) {
    return 'No diff.';
  }
  return 'Content differs.';
}

@immutable
final class _MigrationRecord {
  const _MigrationRecord({
    required this.sourceNamespace,
    required this.sourcePath,
    required this.targetNamespace,
    required this.targetPath,
    this.operationId,
  });

  static _MigrationRecord? fromJson(final Map<String, dynamic> json) {
    final sourceNamespaceValue = json['source_namespace'];
    final targetNamespaceValue = json['target_namespace'];
    final sourcePath = json['source_path'];
    final targetPath = json['target_path'];
    if (sourceNamespaceValue == null ||
        targetNamespaceValue == null ||
        sourcePath == null ||
        targetPath == null) {
      return null;
    }

    return _MigrationRecord(
      sourceNamespace: StorageNamespace.fromJson(sourceNamespaceValue),
      sourcePath: sourcePath.toString(),
      targetNamespace: StorageNamespace.fromJson(targetNamespaceValue),
      targetPath: targetPath.toString(),
      operationId: json['operation_id']?.toString(),
    );
  }

  final StorageNamespace sourceNamespace;
  final String sourcePath;
  final StorageNamespace targetNamespace;
  final String targetPath;
  final String? operationId;

  String get key => '${sourceNamespace.value}:$sourcePath';

  Map<String, dynamic> toJson() => {
    'source_namespace': sourceNamespace.value,
    'source_path': sourcePath,
    'target_namespace': targetNamespace.value,
    'target_path': targetPath,
    if (operationId != null) 'operation_id': operationId,
  };
}

@immutable
final class _MigrationCheckpoint {
  const _MigrationCheckpoint({
    required this.id,
    required this.operationId,
    required this.sourceNamespace,
    required this.targetNamespace,
    required this.sourcePath,
    required this.targetPath,
    required this.status,
    required this.stable,
    this.sourceChecksum,
    this.transformedChecksum,
    this.targetChecksum,
    this.checksumVerified,
    this.spotReadVerified,
    this.transformSteps = const <String>[],
    this.startedAt,
    this.completedAt,
    this.errorMessage,
  });

  static _MigrationCheckpoint? fromJson(final Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final operationId = json['operation_id']?.toString();
    final sourceNamespace = json['source_namespace'];
    final targetNamespace = json['target_namespace'];
    final sourcePath = json['source_path']?.toString();
    final targetPath = json['target_path']?.toString();
    final status = json['status']?.toString();
    if (id == null ||
        id.isEmpty ||
        operationId == null ||
        operationId.isEmpty ||
        sourceNamespace == null ||
        targetNamespace == null ||
        sourcePath == null ||
        sourcePath.isEmpty ||
        targetPath == null ||
        targetPath.isEmpty ||
        status == null ||
        status.isEmpty) {
      return null;
    }

    final transformSteps = json['transform_steps'] is List
        ? (json['transform_steps'] as List<dynamic>)
              .map((final item) => item.toString())
              .where((final value) => value.isNotEmpty)
              .toList(growable: false)
        : const <String>[];

    return _MigrationCheckpoint(
      id: id,
      operationId: operationId,
      sourceNamespace: StorageNamespace.fromJson(sourceNamespace),
      targetNamespace: StorageNamespace.fromJson(targetNamespace),
      sourcePath: sourcePath,
      targetPath: targetPath,
      status: status,
      stable: json['stable'] == true,
      sourceChecksum: json['source_checksum']?.toString(),
      transformedChecksum: json['transformed_checksum']?.toString(),
      targetChecksum: json['target_checksum']?.toString(),
      checksumVerified: json['checksum_verified'] is bool
          ? json['checksum_verified'] as bool
          : null,
      spotReadVerified: json['spot_read_verified'] is bool
          ? json['spot_read_verified'] as bool
          : null,
      transformSteps: transformSteps,
      startedAt: _parseCheckpointDateTime(json['started_at']),
      completedAt: _parseCheckpointDateTime(json['completed_at']),
      errorMessage: json['error_message']?.toString(),
    );
  }

  final String id;
  final String operationId;
  final StorageNamespace sourceNamespace;
  final StorageNamespace targetNamespace;
  final String sourcePath;
  final String targetPath;
  final String status;
  final bool stable;
  final String? sourceChecksum;
  final String? transformedChecksum;
  final String? targetChecksum;
  final bool? checksumVerified;
  final bool? spotReadVerified;
  final List<String> transformSteps;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? errorMessage;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'operation_id': operationId,
    'source_namespace': sourceNamespace.value,
    'target_namespace': targetNamespace.value,
    'source_path': sourcePath,
    'target_path': targetPath,
    'status': status,
    'stable': stable,
    if (sourceChecksum != null) 'source_checksum': sourceChecksum,
    if (transformedChecksum != null)
      'transformed_checksum': transformedChecksum,
    if (targetChecksum != null) 'target_checksum': targetChecksum,
    if (checksumVerified != null) 'checksum_verified': checksumVerified,
    if (spotReadVerified != null) 'spot_read_verified': spotReadVerified,
    if (transformSteps.isNotEmpty) 'transform_steps': transformSteps,
    if (startedAt != null) 'started_at': startedAt!.toUtc().toIso8601String(),
    if (completedAt != null)
      'completed_at': completedAt!.toUtc().toIso8601String(),
    if (errorMessage != null && errorMessage!.isNotEmpty)
      'error_message': errorMessage,
  };
}

@immutable
final class _MigrationTransformedContent {
  const _MigrationTransformedContent({
    required this.content,
    this.steps = const <String>[],
  });

  final String content;
  final List<String> steps;
}

@immutable
final class _MigrationTransformConfig {
  const _MigrationTransformConfig({
    this.pathRemaps = const <_PathPrefixRemap>[],
    this.idRemapTable = const <String, String>{},
    this.schemaTransform,
    this.globalProjection = const _FieldProjection(),
    this.namespaceProjections = const <String, _FieldProjection>{},
  });

  factory _MigrationTransformConfig.fromMetadata(
    final Map<String, dynamic> metadata,
  ) {
    final root = metadata['transform_config'] is Map
        ? <String, dynamic>{
            ...Map<String, dynamic>.from(
              metadata['transform_config'] as Map<dynamic, dynamic>,
            ),
            ...metadata,
          }
        : <String, dynamic>{...metadata};
    final remaps = <_PathPrefixRemap>[];
    final rawPathRemap = root['path_remap'];
    if (rawPathRemap is Map) {
      for (final entry in rawPathRemap.entries) {
        final fromPrefix = _normalizePathValue(entry.key.toString());
        final toPrefix = _normalizePathValue(entry.value?.toString() ?? '');
        if (fromPrefix.isEmpty) {
          continue;
        }
        remaps.add(
          _PathPrefixRemap(fromPrefix: fromPrefix, toPrefix: toPrefix),
        );
      }
    }
    final rawPathRemapRules = root['path_remap_rules'];
    if (rawPathRemapRules is List) {
      for (final item in rawPathRemapRules) {
        if (item is! Map) {
          continue;
        }
        final fromRaw = item['from']?.toString() ?? '';
        final toRaw = item['to']?.toString() ?? '';
        final fromPrefix = _normalizePathValue(fromRaw);
        if (fromPrefix.isEmpty) {
          continue;
        }
        remaps.add(
          _PathPrefixRemap(
            fromPrefix: fromPrefix,
            toPrefix: _normalizePathValue(toRaw),
          ),
        );
      }
    }
    remaps.sort(
      (final left, final right) =>
          right.fromPrefix.length.compareTo(left.fromPrefix.length),
    );

    final idRemap = <String, String>{};
    final rawIdRemap = root['id_remap_table'];
    if (rawIdRemap is Map) {
      for (final entry in rawIdRemap.entries) {
        final from = entry.key.toString();
        final to = entry.value?.toString() ?? '';
        if (from.isEmpty || to.isEmpty) {
          continue;
        }
        idRemap[from] = to;
      }
    }

    _SchemaTransformRule? schemaTransform;
    final rawSchemaTransform = root['schema_transform'];
    if (rawSchemaTransform is Map) {
      final toVersion = rawSchemaTransform['to']?.toString();
      final fieldName =
          rawSchemaTransform['field']?.toString() ??
          rawSchemaTransform['version_field']?.toString() ??
          'schema_version';
      if (toVersion != null && toVersion.isNotEmpty) {
        schemaTransform = _SchemaTransformRule(
          fieldName: fieldName,
          toVersion: toVersion,
          fromVersion: rawSchemaTransform['from']?.toString(),
        );
      }
    }

    final rawProjection = root['field_projection'];
    var globalProjection = const _FieldProjection();
    final namespaceProjections = <String, _FieldProjection>{};
    if (rawProjection is Map) {
      final projectionMap = Map<String, dynamic>.from(rawProjection);
      globalProjection = _FieldProjection.fromJson(projectionMap);
      for (final entry in projectionMap.entries) {
        if (entry.key == 'include' || entry.key == 'exclude') {
          continue;
        }
        if (entry.value is! Map) {
          continue;
        }
        final projection = _FieldProjection.fromJson(
          Map<String, dynamic>.from(entry.value as Map<dynamic, dynamic>),
        );
        if (projection.hasRules) {
          namespaceProjections[entry.key] = projection;
        }
      }
    }

    return _MigrationTransformConfig(
      pathRemaps: remaps,
      idRemapTable: idRemap,
      schemaTransform: schemaTransform,
      globalProjection: globalProjection,
      namespaceProjections: namespaceProjections,
    );
  }

  final List<_PathPrefixRemap> pathRemaps;
  final Map<String, String> idRemapTable;
  final _SchemaTransformRule? schemaTransform;
  final _FieldProjection globalProjection;
  final Map<String, _FieldProjection> namespaceProjections;

  bool get hasTransforms =>
      pathRemaps.isNotEmpty ||
      idRemapTable.isNotEmpty ||
      schemaTransform != null ||
      globalProjection.hasRules ||
      namespaceProjections.isNotEmpty;

  String transformPath(final String sourcePath) {
    var path = _normalizePathValue(sourcePath);
    if (path.isEmpty) {
      return path;
    }

    for (final remap in pathRemaps) {
      if (path == remap.fromPrefix) {
        path = remap.toPrefix;
        continue;
      }
      if (path.startsWith('${remap.fromPrefix}/')) {
        final suffix = path.substring(remap.fromPrefix.length + 1);
        path = remap.toPrefix.isEmpty ? suffix : '${remap.toPrefix}/$suffix';
      }
    }

    if (idRemapTable.isNotEmpty) {
      final segments = path
          .split('/')
          .where((final segment) => segment.isNotEmpty)
          .map((final segment) => idRemapTable[segment] ?? segment)
          .toList(growable: false);
      path = segments.join('/');
    }

    return _normalizePathValue(path);
  }

  _MigrationTransformedContent transformContent({
    required final StorageNamespace sourceNamespace,
    required final StorageNamespace targetNamespace,
    required final String sourcePath,
    required final String targetPath,
    required final String sourceContent,
  }) {
    if (!hasTransforms) {
      return _MigrationTransformedContent(content: sourceContent);
    }

    var content = sourceContent;
    final steps = <String>[];
    final projection =
        namespaceProjections[targetNamespace.value] ??
        namespaceProjections[sourceNamespace.value] ??
        globalProjection;
    final requiresJson =
        schemaTransform != null ||
        projection.hasRules ||
        idRemapTable.isNotEmpty;
    Object? decoded;
    var decodedJson = false;

    if (requiresJson) {
      try {
        decoded = jsonDecode(content);
        decodedJson = true;
      } on FormatException {
        if (schemaTransform != null || projection.hasRules) {
          throw FormatException(
            'JSON transform failed for $sourcePath -> $targetPath. '
            'Content is not valid JSON.',
          );
        }
      }
    }

    if (decodedJson && idRemapTable.isNotEmpty) {
      decoded = _remapJsonIds(decoded, idRemapTable);
      steps.add('id_remap_table');
    }

    if (decodedJson && schemaTransform != null) {
      final applied = schemaTransform!.apply(decoded);
      if (applied) {
        steps.add('schema_transform');
      }
    }

    if (decodedJson && projection.hasRules) {
      decoded = projection.apply(decoded);
      steps.add('field_projection');
    }

    if (decodedJson) {
      content = jsonEncode(decoded);
    }
    return _MigrationTransformedContent(content: content, steps: steps);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (pathRemaps.isNotEmpty)
      'path_remap_rules': <Map<String, String>>[
        for (final remap in pathRemaps)
          <String, String>{'from': remap.fromPrefix, 'to': remap.toPrefix},
      ],
    if (idRemapTable.isNotEmpty) 'id_remap_table': idRemapTable,
    if (schemaTransform != null) 'schema_transform': schemaTransform!.toJson(),
    if (globalProjection.hasRules || namespaceProjections.isNotEmpty)
      'field_projection': <String, dynamic>{
        ...globalProjection.toJson(),
        for (final entry in namespaceProjections.entries)
          entry.key: entry.value.toJson(),
      },
  };
}

@immutable
final class _PathPrefixRemap {
  const _PathPrefixRemap({required this.fromPrefix, required this.toPrefix});

  final String fromPrefix;
  final String toPrefix;
}

@immutable
final class _SchemaTransformRule {
  const _SchemaTransformRule({
    required this.fieldName,
    required this.toVersion,
    this.fromVersion,
  });

  final String fieldName;
  final String toVersion;
  final String? fromVersion;

  bool apply(final Object? node) {
    if (node is! Map) {
      throw const FormatException(
        'Schema transform expects top-level JSON object.',
      );
    }
    if (fromVersion != null && node[fieldName]?.toString() != fromVersion) {
      return false;
    }
    if (node[fieldName]?.toString() == toVersion) {
      return false;
    }
    node[fieldName] = toVersion;
    return true;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'field': fieldName,
    'to': toVersion,
    if (fromVersion != null) 'from': fromVersion,
  };
}

@immutable
final class _FieldProjection {
  const _FieldProjection({
    this.include = const <String>{},
    this.exclude = const <String>{},
  });

  factory _FieldProjection.fromJson(final Map<String, dynamic> json) =>
      _FieldProjection(
        include: _stringSetFromValue(json['include']),
        exclude: _stringSetFromValue(json['exclude']),
      );

  final Set<String> include;
  final Set<String> exclude;

  bool get hasRules => include.isNotEmpty || exclude.isNotEmpty;

  Object? apply(final Object? node) {
    if (node is! Map) {
      throw const FormatException(
        'Field projection expects top-level JSON object.',
      );
    }
    final source = Map<String, dynamic>.from(
      node.map((final key, final value) => MapEntry(key.toString(), value)),
    );

    var result = <String, dynamic>{...source};
    if (include.isNotEmpty) {
      result = <String, dynamic>{
        for (final entry in result.entries)
          if (include.contains(entry.key)) entry.key: entry.value,
      };
    }
    if (exclude.isNotEmpty) {
      result.removeWhere((final key, final _) => exclude.contains(key));
    }
    return result;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (include.isNotEmpty) 'include': include.toList(growable: false),
    if (exclude.isNotEmpty) 'exclude': exclude.toList(growable: false),
  };
}

@immutable
final class _MigrationLockInfo {
  const _MigrationLockInfo({this.owner, this.acquiredAt});

  final String? owner;
  final DateTime? acquiredAt;
}

Object? _remapJsonIds(final Object? node, final Map<String, String> idRemap) {
  if (node is Map) {
    return <String, dynamic>{
      for (final entry in node.entries)
        entry.key.toString(): _remapJsonIds(entry.value, idRemap),
    };
  }
  if (node is List) {
    return node.map((final item) => _remapJsonIds(item, idRemap)).toList();
  }
  if (node is String) {
    return idRemap[node] ?? node;
  }
  return node;
}

DateTime? _parseCheckpointDateTime(final Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

Set<String> _stringSetFromValue(final Object? value) {
  if (value is! List) {
    return const <String>{};
  }
  return value
      .map((final item) => item.toString())
      .where((final item) => item.isNotEmpty)
      .toSet();
}

String _normalizePathValue(final String path) => path
    .replaceAll(r'\', '/')
    .replaceAll(RegExp('/+'), '/')
    .replaceAll(RegExp('^/+'), '')
    .replaceAll(RegExp(r'/+$'), '');
