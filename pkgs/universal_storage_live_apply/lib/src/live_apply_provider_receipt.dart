/// Bounded observations reported by an actual native provider effect.
library;

import 'dart:convert';

/// The transaction phase that invoked the observed provider effect.
enum LiveApplyReceiptPhase {
  /// A dispatched forward mutation.
  forward,

  /// A dispatched inverse mutation.
  inverse,
}

/// Maximum retained provider observations for one journaled path.
const liveApplyMaxProviderReceipts = 1024;

/// Selected durability metadata; grants no permission or replay authority.
/// Missing metadata records no receipt. It cannot infer an unobserved effect
/// after a crash or assert containment or power-loss durability.
class LiveApplyProviderReceipt {
  /// Construct an observation; serialization and admission validate its bounds.
  const LiveApplyProviderReceipt({
    required this.phase,
    required this.durabilityProtocol,
    required this.namespace,
    required this.sequence,
    required this.operationId,
    required this.checkpointSequence,
  });

  /// Maximum retained observations per path, including an inverse receipt.
  static const maxReceipts = liveApplyMaxProviderReceipts;

  /// Native invocation phase; never supplied by provider metadata.
  final LiveApplyReceiptPhase phase;

  /// The provider's declared durability protocol.
  final String durabilityProtocol;

  /// The provider's durability namespace, not an executable path.
  final String namespace;

  /// The sequence reported for this effect.
  final int sequence;

  /// The provider's opaque operation identifier.
  final String operationId;

  /// The checkpoint sequence reported after the effect.
  final int checkpointSequence;

  /// Reject unsupported or unbounded observations at runtime.
  void validate() {
    if (durabilityProtocol != 'journal_v1' ||
        !_boundedText(namespace, 256) ||
        !_boundedText(operationId, 512) ||
        sequence < 1 ||
        checkpointSequence < sequence ||
        checkpointSequence > 9007199254740991) {
      throw const FormatException('invalid live-apply provider receipt');
    }
  }

  /// Serialize only the selected native observation fields.
  Map<String, dynamic> toMap() {
    validate();
    return {
      'phase': phase.name,
      'durability_protocol': durabilityProtocol,
      'namespace': namespace,
      'sequence': sequence,
      'operation_id': operationId,
      'checkpoint_sequence': checkpointSequence,
    };
  }

  /// Read a bounded observation without retaining arbitrary metadata.
  // ignore: prefer_constructors_over_static_methods
  static LiveApplyProviderReceipt fromMap(Map<String, dynamic> map) {
    const fields = {
      'phase',
      'durability_protocol',
      'namespace',
      'sequence',
      'operation_id',
      'checkpoint_sequence',
    };
    if (map.length != fields.length ||
        !map.keys.every(fields.contains) ||
        map['durability_protocol'] is! String ||
        map['namespace'] is! String ||
        map['sequence'] is! int ||
        map['operation_id'] is! String ||
        map['checkpoint_sequence'] is! int) {
      throw const FormatException('invalid live-apply provider receipt');
    }
    final phase = switch (map['phase']) {
      'forward' => LiveApplyReceiptPhase.forward,
      'inverse' => LiveApplyReceiptPhase.inverse,
      _ => throw const FormatException(
        'invalid live-apply provider receipt phase',
      ),
    };
    final receipt = LiveApplyProviderReceipt(
      phase: phase,
      durabilityProtocol: map['durability_protocol'] as String,
      namespace: map['namespace'] as String,
      sequence: map['sequence'] as int,
      operationId: map['operation_id'] as String,
      checkpointSequence: map['checkpoint_sequence'] as int,
    );
    return receipt..validate();
  }

  /// Select the provider's advertised durability fields after a real effect.
  /// Unrelated metadata alone yields no receipt; partial advertisements refuse.
  // ignore: prefer_constructors_over_static_methods
  static LiveApplyProviderReceipt? fromMetadata(
    Map<String, dynamic> metadata, {
    required LiveApplyReceiptPhase phase,
  }) {
    const fields = {
      'durability_protocol',
      'durability_namespace',
      'durability_sequence',
      'durability_operation_id',
      'durability_checkpoint_sequence',
    };
    if (!fields.any(metadata.containsKey)) return null;
    return fromMap({
      'phase': phase.name,
      'durability_protocol': metadata['durability_protocol'],
      'namespace': metadata['durability_namespace'],
      'sequence': metadata['durability_sequence'],
      'operation_id': metadata['durability_operation_id'],
      'checkpoint_sequence': metadata['durability_checkpoint_sequence'],
    });
  }
}

bool _boundedText(String value, int maxBytes) =>
    value.isNotEmpty &&
    utf8.encode(value).length <= maxBytes &&
    !value.runes.any((code) => code < 32 || code == 127);
