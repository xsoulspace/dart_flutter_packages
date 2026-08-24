import 'package:meta/meta.dart';

import 'hlc.dart';

/// One immutable convergence event (ADR 0011 §2).
///
/// [opId] is derived deterministically from `(docId, hlc)` — an actor can
/// issue at most one op per HLC tick, so the pair is unique and no random
/// ids are needed.
@immutable
final class OpRecord {
  const OpRecord({
    required this.docId,
    required this.hlc,
    required this.payload,
  }) : assert(docId != '');

  factory OpRecord.fromJson(final Map<String, dynamic> json) => OpRecord(
    docId: json['doc_id'] as String,
    hlc: hlcFromJson(json['hlc']),
    payload: Map<String, dynamic>.from(json['payload'] as Map<dynamic, dynamic>),
  );

  final String docId;
  final Hlc hlc;

  /// Strategy-interpretable JSON-encodable payload.
  final Map<String, dynamic> payload;

  String get opId => '$docId#${hlc.wallMillis}#${hlc.counter}#${hlc.actorId}';
  String get actorId => hlc.actorId;

  Map<String, dynamic> toJson() => {
    'doc_id': docId,
    'hlc': hlc.toJson(),
    'payload': payload,
  };

  @override
  String toString() => 'OpRecord($opId)';
}
