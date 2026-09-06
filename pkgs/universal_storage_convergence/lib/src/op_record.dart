import 'package:meta/meta.dart';

import 'hlc.dart';

/// One immutable convergence event (ADR 0011 §2).
///
/// [opId] is derived deterministically from `(docId, hlc)` — an actor can
/// issue at most one op per HLC tick, so the pair is unique and no random
/// ids are needed.
///
/// [ttl] marks an **ephemeral op** (ADR 0029 §1): it rides the normal
/// convergence path (same dedupe, same ordering) but never folds into
/// durable state or snapshots, never advances the durable version vector,
/// and is dropped once expired. Ephemeral expiry is measured from the
/// issuing op's HLC wall clock.
@immutable
final class OpRecord {
  const OpRecord({
    required this.docId,
    required this.hlc,
    required this.payload,
    this.ttl,
  }) : assert(docId != '');

  factory OpRecord.fromJson(final Map<String, dynamic> json) => OpRecord(
    docId: json['doc_id'] as String,
    hlc: hlcFromJson(json['hlc']),
    payload: Map<String, dynamic>.from(json['payload'] as Map<dynamic, dynamic>),
    ttl:
        json['ttl_ms'] == null
            ? null
            : Duration(milliseconds: (json['ttl_ms'] as num).toInt()),
  );

  final String docId;
  final Hlc hlc;

  /// Strategy-interpretable JSON-encodable payload.
  final Map<String, dynamic> payload;

  /// Non-null for ephemeral ops (ADR 0029 §1); null for durable ops.
  final Duration? ttl;

  String get opId => '$docId#${hlc.wallMillis}#${hlc.counter}#${hlc.actorId}';
  String get actorId => hlc.actorId;

  /// True when this op's TTL has elapsed relative to [now].
  bool isExpiredAt(final DateTime now) =>
      ttl != null &&
      now.isAfter(
        DateTime.fromMillisecondsSinceEpoch(hlc.wallMillis).add(ttl!),
      );

  Map<String, dynamic> toJson() => {
    'doc_id': docId,
    'hlc': hlc.toJson(),
    'payload': payload,
    if (ttl != null) 'ttl_ms': ttl!.inMilliseconds,
  };

  @override
  String toString() => 'OpRecord($opId)';
}
