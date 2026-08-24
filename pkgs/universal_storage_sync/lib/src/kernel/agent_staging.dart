import 'package:universal_storage_interface/universal_storage_interface.dart';

import '../sync_queue_store.dart';
import 'outbox.dart';

/// Namespace where agent-proposed edits are staged before review.
///
/// Agents never write into document namespaces directly; proposals land here
/// as outbox entries, are surfaced for human review, and are either promoted
/// (copied into the target namespace and enqueued for sync) or dropped.
final class AgentStagingNamespace {
  const AgentStagingNamespace._();

  static const StorageNamespace namespace = StorageNamespace('agent-drafts');
}

/// A single agent-proposed edit awaiting review.
class AgentProposal {
  const AgentProposal({
    required this.entryId,
    required this.path,
    required this.content,
    required this.agentId,
    required this.stagedAtUtc,
    this.message = '',
  });

  final String entryId;
  final String path;
  final String content;
  final String agentId;
  final DateTime stagedAtUtc;
  final String message;
}

/// Stages, lists, promotes, and drops agent-proposed edits using the
/// durable outbox of the `agent-drafts` namespace.
///
/// All state transitions go through [SyncQueueStore.mutateState], so
/// concurrent agents and UI reviews never lose entries.
final class AgentEditStager {
  AgentEditStager({required SyncQueueStore queueStore}) : _queueStore = queueStore;

  final SyncQueueStore _queueStore;

  /// Stages a proposed edit. Returns the deterministic proposal id; staging
  /// identical content for the same path twice collapses to one entry.
  Future<String> stage({
    required StorageService service,
    required String path,
    required String content,
    String agentId = 'unknown-agent',
    String message = '',
  }) async {
    final now = DateTime.now().toUtc();
    final digest = hashString(content);
    final entryId = deterministicEntryId(
      namespace: AgentStagingNamespace.namespace,
      operation: SyncQueueOperationType.write,
      path: path,
      seed: digest,
    );
    final entry = SyncOutboxEntry(
      id: entryId,
      namespace: AgentStagingNamespace.namespace,
      operation: SyncQueueOperationType.write,
      path: path,
      createdAtUtc: now,
      updatedAtUtc: now,
      message: message,
      contentDigest: digest,
      metadata: <String, dynamic>{'agent_id': agentId},
    );

    await _queueStore.mutateState(
      namespace: AgentStagingNamespace.namespace,
      service: service,
      update: (final state) async => state.copyWith(
        outbox: <SyncOutboxEntry>[
          ...state.outbox.where((e) => e.id != entryId),
          entry,
        ],
      ),
    );

    // Store proposal payload in a dedicated draft file keyed by entry id.
    await service.saveFile(
      _proposalPath(entryId),
      content,
      message: message.isEmpty ? 'stage agent proposal' : message,
    );

    return entryId;
  }

  /// Lists all pending proposals (best-effort read of staged files).
  Future<List<AgentProposal>> listPending({
    required StorageService service,
  }) async {
    final state = await _queueStore.loadState(
      namespace: AgentStagingNamespace.namespace,
      service: service,
    );
    final proposals = <AgentProposal>[];
    for (final entry in state.outbox) {
      final content = await service.readFile(_proposalPath(entry.id));
      if (content == null) continue;
      proposals.add(
        AgentProposal(
          entryId: entry.id,
          path: entry.path,
          content: content,
          agentId: entry.metadata['agent_id']?.toString() ?? 'unknown-agent',
          stagedAtUtc: entry.createdAtUtc,
          message: entry.message,
        ),
      );
    }
    return proposals;
  }

  /// Promotes a proposal: writes [content] into [targetPath] of the target
  /// [namespaceProfile] and removes the staged draft. Returns the
  /// [FileOperationResult] from the promotion write.
  Future<FileOperationResult> promote({
    required StorageService service,
    required StorageNamespaceProfile namespaceProfile,
    required String entryId,
    required String targetPath,
    required String content,
    String? message,
  }) async {
    final result = await service.saveFile(
      targetPath,
      content,
      message: message ?? 'promote agent proposal $entryId',
    );
    await _dropEntry(service: service, entryId: entryId);
    return result;
  }

  /// Drops a staged proposal without promoting it.
  Future<void> drop({
    required StorageService service,
    required String entryId,
  }) => _dropEntry(service: service, entryId: entryId);

  Future<void> _dropEntry({
    required StorageService service,
    required String entryId,
  }) async {
    try {
      await service.removeFile(_proposalPath(entryId));
    } on Object {
      // Draft file may already be gone; dropping the queue entry is enough.
    }
    await _queueStore.mutateState(
      namespace: AgentStagingNamespace.namespace,
      service: service,
      update: (final state) async => state.copyWith(
        outbox: state.outbox.where((e) => e.id != entryId).toList(),
      ),
    );
  }

  static String _proposalPath(String entryId) =>
      '.us/agent-proposals/$entryId.md';
}
