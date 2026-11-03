import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// permission_gate.v1 — the LIVE slot of the perm decision head (RUNG-1 of
/// the nursery, ADR-style ledger: `pkgs/xsoulspace_inference_mlx_native/
/// ROADMAP.md` §1 and `RESULTS-HISTORY.md` §14–§16).
///
/// What is shipped here is deliberately the MEASURED behavior, not a
/// model: the dense line closed with data (attempts 4–7 — every calibrated
/// operating point on the 16M trunk degenerates to all-abstain; the best
/// zero-unsafe operating point IS all-abstain), and the gate has never run
/// live. This class is the live slot that changes that: it answers real
/// permission questions with the shipped law —
///
///   **the gate never allows.** Every gated question returns [abstain];
///   the host keeps decision authority (it may proceed under its own
///   policy, or stop) — and the question lands in the escalation store as
///   one human-labelable example, the cheapest future training data the
///   lane has named (ROADMAP §1 "live escalations as data").
///
/// Zero-unsafe is BY CONSTRUCTION here: an answer set that contains no
/// allow cannot commit an unsafe allow. The measured agreement of the
/// shipped behavior (0.667 on the frozen 18) is a bench fact, NOT claimed
/// live — the live-slot acceptance record (real answer quality) is written
/// only from accumulated labeled outcomes, never assumed.
///
/// The store is append-only JSONL: questions are hashed (no raw payloads
/// need to persist), outcomes are appended as separate records, and
/// history is never rewritten. `recordOutcome` is the host's label write;
/// [labeledCount] is the live-slot acceptance metric in the making.
final class LayaPermGateV1 {
  LayaPermGateV1({required this.storePath, this.source = 'laya_perm_gate_v1'});

  /// Append-only JSONL file backing the escalation store. Created on
  /// first write; every record is one line of canonical JSON.
  final String storePath;

  /// Attribution source stamped on every record.
  final String source;

  /// The only answer the shipped law produces (v1).
  static const String abstain = 'abstain';

  static const String schema = 'perm_gate_v1';

  int _escalationCounter = 0;

  /// The gate's decision for one permission question. ALWAYS [abstain] in
  /// v1 — recorded as an escalation awaiting the host's label.
  PermGateDecision decide({
    required String operation,
    required String target,
    String? context,
  }) {
    final question = <String, Object?>{
      'operation': operation,
      'target': target,
      'context': ?context,
    };
    final digest = sha256.convert(utf8.encode(jsonEncode(question))).toString();
    final escalation = PermGateEscalation(
      id: 'pg-${DateTime.now().toUtc().microsecondsSinceEpoch}'
          '-${_escalationCounter++}',
      targetDigest: digest,
      operation: operation,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    _append(<String, Object?>{
      'ts': escalation.createdAt,
      'schema': schema,
      'escalation_id': escalation.id,
      'operation': operation,
      'target_digest': digest,
      if (context != null)
        'context_digest':
            sha256.convert(utf8.encode(context)).toString(),
      'answer': abstain,
      'outcome': null,
      'source': source,
    });
    return PermGateDecision(answer: abstain, escalation: escalation);
  }

  /// The host's label for a recorded escalation — `allowed` or `denied`.
  /// Appended as its own record (the store is append-only; the original
  /// escalation line is never rewritten).
  void recordOutcome({
    required String escalationId,
    required String outcome,
  }) {
    if (outcome != 'allowed' && outcome != 'denied') {
      throw ArgumentError.value(outcome, 'outcome', 'must be allowed|denied');
    }
    _append(<String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'schema': schema,
      'escalation_id': escalationId,
      'outcome': outcome,
      'source': source,
    });
  }

  /// Every record in the store, in append order. Escalations carry
  /// `answer: abstain`; outcomes carry a non-null `outcome`. A store that
  /// does not exist yet reads as empty.
  List<Map<String, Object?>> readRecords() {
    final file = File(storePath);
    if (!file.existsSync()) {
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      for (final line
          in file.readAsLinesSync().where((line) => line.trim().isNotEmpty))
        jsonDecode(line) as Map<String, Object?>,
    ];
  }

  /// Escalations recorded so far.
  int get escalationCount =>
      readRecords().where((r) => r['answer'] != null).length;

  /// Escalations the host has labeled — the live-slot acceptance metric
  /// in the making (real answer quality is computed from these, once they
  /// exist; it is never assumed).
  int get labeledCount =>
      readRecords().where((r) => r['outcome'] != null).length;

  void _append(Map<String, Object?> record) {
    final file = File(storePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

/// The gate's answer plus the escalation record it produced.
final class PermGateDecision {
  const PermGateDecision({required this.answer, required this.escalation});

  /// Always [LayaPermGateV1.abstain] in v1 — the gate never allows.
  final String answer;
  final PermGateEscalation escalation;
}

/// One recorded escalation: identity, question digest, and timestamp.
/// Pass [id] to [LayaPermGateV1.recordOutcome] once the host decides.
final class PermGateEscalation {
  const PermGateEscalation({
    required this.id,
    required this.targetDigest,
    required this.operation,
    required this.createdAt,
  });

  final String id;
  final String targetDigest;
  final String operation;
  final String createdAt;
}
