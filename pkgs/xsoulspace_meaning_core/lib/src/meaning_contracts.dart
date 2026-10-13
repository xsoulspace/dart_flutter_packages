import 'package:agentic_executables_wire/agentic_executables_wire.dart';
import 'package:intentcall_schema/intentcall_schema.dart';

/// Opaque native address. The namespace names the owning adapter; no parsing
/// or correspondence is inferred from a label or from equal ids.
final class MeaningRef {
  factory MeaningRef.fromJson(Map<String, Object?> json) => MeaningRef(
    namespace: _string(json, 'namespace'),
    id: _string(json, 'id'),
  );
  MeaningRef({required this.namespace, required this.id}) {
    if (namespace.isEmpty || id.isEmpty) {
      throw ArgumentError('meaning_ref_requires_namespace_and_id');
    }
  }
  final String namespace;
  final String id;

  Map<String, Object?> toJson() => {'namespace': namespace, 'id': id};
}

/// Owner-defined revision kind (e.g. source_sha256, observation, version_vector).
/// Values of different kinds are never compared or converted by this library.
final class MeaningRevision {
  factory MeaningRevision.fromJson(Map<String, Object?> json) =>
      MeaningRevision(
        kind: _string(json, 'kind'),
        value: _string(json, 'value'),
      );
  MeaningRevision({required this.kind, required this.value}) {
    if (kind.isEmpty || value.isEmpty) {
      throw ArgumentError('meaning_revision_requires_kind_and_value');
    }
  }
  final String kind;
  final String value;
  Map<String, Object?> toJson() => {'kind': kind, 'value': value};
}

final class MeaningDependency {
  factory MeaningDependency.fromJson(Map<String, Object?> json) =>
      MeaningDependency(
        ref: MeaningRef.fromJson(_object(json['ref'])),
        revision: MeaningRevision.fromJson(_object(json['revision'])),
      );
  const MeaningDependency({required this.ref, required this.revision});
  final MeaningRef ref;
  final MeaningRevision revision;
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'revision': revision.toJson(),
  };
}

enum MeaningEvidenceStage { observed, predicted, previewExecuted, applied }

enum MeaningCorrespondenceKind { exact, candidate, unsupported }

enum MeaningRecoveryKind {
  exactInverse,
  compensation,
  isolatedDiscard,
  unavailable,
}

/// Addressable originals are retained by the owner, not flattened into labels.
final class MeaningEvidence {
  factory MeaningEvidence.fromJson(Map<String, Object?> json) =>
      MeaningEvidence(
        ref: MeaningRef.fromJson(_object(json['ref'])),
        stage: _enum(MeaningEvidenceStage.values, json['stage']),
      );
  const MeaningEvidence({required this.ref, required this.stage});
  final MeaningRef ref;
  final MeaningEvidenceStage stage;
  Map<String, Object?> toJson() => {'ref': ref.toJson(), 'stage': stage.name};
}

/// A revision-bound assertion linking two views, backed by named evidence.
/// Even an exact assertion is not permission to mutate either endpoint.
final class MeaningCorrespondence {
  factory MeaningCorrespondence.fromJson(Map<String, Object?> json) =>
      MeaningCorrespondence(
        from: MeaningDependency.fromJson(_object(json['from'])),
        to: MeaningDependency.fromJson(_object(json['to'])),
        kind: _enum(MeaningCorrespondenceKind.values, json['kind']),
        evidence: [
          for (final e in _list(json['evidence']))
            MeaningEvidence.fromJson(_object(e)),
        ],
      );
  MeaningCorrespondence({
    required this.from,
    required this.to,
    required this.kind,
    required List<MeaningEvidence> evidence,
  }) : evidence = List.unmodifiable(evidence) {
    if (evidence.isEmpty) {
      throw ArgumentError('correspondence_requires_evidence');
    }
    if (kind == MeaningCorrespondenceKind.exact &&
        evidence.every((e) => e.stage == MeaningEvidenceStage.predicted)) {
      throw ArgumentError('predictions_do_not_establish_exact_correspondence');
    }
  }
  final MeaningDependency from;
  final MeaningDependency to;
  final MeaningCorrespondenceKind kind;
  final List<MeaningEvidence> evidence;
  Map<String, Object?> toJson() => {
    'from': from.toJson(),
    'to': to.toJson(),
    'kind': kind.name,
    'evidence': [for (final e in evidence) e.toJson()],
  };
}

/// Native operation metadata. Reuses IntentCall validation and, where present,
/// the actual AE executable wire. No second schema algebra or executor.
final class MeaningOperation {
  factory MeaningOperation.fromJson(Map<String, Object?> json) =>
      MeaningOperation(
        ref: MeaningRef.fromJson(_object(json['ref'])),
        inputSchema: _object(json['input_schema']),
        executable: json['executable'] == null
            ? null
            : EditExecutableWire.fromJson(_object(json['executable'])),
      );
  MeaningOperation({
    required this.ref,
    required InputSchema inputSchema,
    EditExecutableWire? executable,
  }) : inputSchema = _freezeMap(inputSchema),
       executable = executable == null
           ? null
           : EditExecutableWire(
               id: executable.id,
               kind: executable.kind,
               params: List.unmodifiable(executable.params),
               verification: List.unmodifiable(executable.verification),
               scope: executable.scope,
               description: executable.description,
             );
  final MeaningRef ref;
  final InputSchema inputSchema;
  final EditExecutableWire? executable;
  void validate(AgentArguments arguments) =>
      validateAgainstSchema(inputSchema, arguments);
  Map<String, Object?> toJson() => {
    'ref': ref.toJson(),
    'input_schema': inputSchema,
    if (executable != null) 'executable': executable!.toJson(),
  };
}

/// Describes recovery offered by the native owner. This is neither a journal
/// nor a guarantee; the owner verifies conditions at invocation time.
final class MeaningRecovery {
  factory MeaningRecovery.fromJson(Map<String, Object?> json) =>
      MeaningRecovery(
        kind: _enum(MeaningRecoveryKind.values, json['kind']),
        operation: json['operation'] == null
            ? null
            : MeaningRef.fromJson(_object(json['operation'])),
        conditions: [
          for (final d in _list(json['conditions']))
            MeaningDependency.fromJson(_object(d)),
        ],
      );
  MeaningRecovery({
    required this.kind,
    this.operation,
    required List<MeaningDependency> conditions,
  }) : conditions = List.unmodifiable(conditions) {
    if (kind != MeaningRecoveryKind.unavailable && operation == null) {
      throw ArgumentError('available_recovery_requires_native_operation');
    }
  }
  final MeaningRecoveryKind kind;
  final MeaningRef? operation;
  final List<MeaningDependency> conditions;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (operation != null) 'operation': operation!.toJson(),
    'conditions': [for (final d in conditions) d.toJson()],
  };
}

/// Frozen candidate description, never an execution/adoption receipt.
/// The host binds consent, checks dependencies, verifies the footprint and
/// records effects. Only native owners interpret operation ids and revisions.
final class MeaningChange {
  factory MeaningChange.fromJson(Map<String, Object?> json) {
    if (json['schema'] != 'xsoulspace.meaning_change.v1') {
      throw ArgumentError('unsupported_meaning_change_schema');
    }
    return MeaningChange(
      operation: MeaningOperation.fromJson(_object(json['operation'])),
      arguments: _object(json['arguments']),
      reads: [
        for (final d in _list(json['reads']))
          MeaningDependency.fromJson(_object(d)),
      ],
      writes: [
        for (final r in _list(json['writes'])) MeaningRef.fromJson(_object(r)),
      ],
      predictions: [
        for (final e in _list(json['predictions']))
          MeaningEvidence.fromJson(_object(e)),
      ],
      recovery: MeaningRecovery.fromJson(_object(json['recovery'])),
    );
  }
  MeaningChange({
    required this.operation,
    required AgentArguments arguments,
    required List<MeaningDependency> reads,
    required List<MeaningRef> writes,
    required List<MeaningEvidence> predictions,
    required this.recovery,
  }) : arguments = _freezeMap(arguments),
       reads = List.unmodifiable(reads),
       writes = List.unmodifiable(writes),
       predictions = List.unmodifiable(predictions) {
    operation.validate(this.arguments);
    if (predictions.any((e) => e.stage != MeaningEvidenceStage.predicted)) {
      throw ArgumentError('change_predictions_require_predicted_evidence');
    }
  }
  final MeaningOperation operation;
  final AgentArguments arguments;
  final List<MeaningDependency> reads;
  final List<MeaningRef> writes;
  final List<MeaningEvidence> predictions;
  final MeaningRecovery recovery;
  Map<String, Object?> toJson() => {
    'schema': 'xsoulspace.meaning_change.v1',
    'operation': operation.toJson(),
    'arguments': arguments,
    'reads': [for (final d in reads) d.toJson()],
    'writes': [for (final r in writes) r.toJson()],
    'predictions': [for (final e in predictions) e.toJson()],
    'recovery': recovery.toJson(),
  };
}

Map<String, Object?> _freezeMap(Map<String, Object?> map) =>
    Map.unmodifiable(map.map((k, v) => MapEntry(k, _freeze(v))));
Object? _freeze(Object? value) {
  if (value is Map<String, Object?>) return _freezeMap(value);
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  if (value == null ||
      value is String ||
      value is bool ||
      value is int ||
      (value is double && value.isFinite)) {
    return value;
  }
  throw ArgumentError('meaning_contract_requires_json_values');
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw ArgumentError('meaning_contract_requires_object');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) {
    throw ArgumentError('meaning_contract_requires_array');
  }
  return value;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw ArgumentError('meaning_contract_requires_$key');
  return value;
}

T _enum<T extends Enum>(List<T> values, Object? name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw ArgumentError('unsupported_meaning_contract_enum: $name');
}
