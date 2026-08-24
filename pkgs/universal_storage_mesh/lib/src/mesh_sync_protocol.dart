import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// Wire envelopes for mesh anti-entropy exchanges (ADR 0010 §4).
///
/// The protocol is symmetric and single-round:
/// 1. both sides send `hello` + `vv`
/// 2. both sides compute what the peer lacks and send `delta`
/// 3. both sides apply the incoming `delta` and close
///
/// No side is authoritative — convergence is decided by the kernel at every
/// replica identically (ADR 0010 §2).
@internal
final class MeshSyncProtocol {
  static const helloType = 'hello';
  static const vvType = 'vv';
  static const deltaType = 'delta';

  static Uint8List encode(final Map<String, Object?> message) =>
      Uint8List.fromList(utf8.encode(jsonEncode(message)));

  static Map<String, Object?> decode(final Uint8List bytes) =>
      Map<String, Object?>.from(
        jsonDecode(utf8.decode(bytes)) as Map<dynamic, dynamic>,
      );

  static Map<String, Object?> hello({
    required final String peerId,
    required final String displayName,
  }) => {'type': helloType, 'peer_id': peerId, 'display_name': displayName};

  /// Per-document version vectors: `{docId: {actor: hlc}}`.
  static Map<String, Object?> vv(
    final Map<String, VersionVector> docVectors,
  ) => {
    'type': vvType,
    'docs': {
      for (final entry in docVectors.entries) entry.key: entry.value.toJson(),
    },
  };

  static Map<String, VersionVector> parseVv(final Object? raw) {
    final docs =
        (raw as Map<dynamic, dynamic>)['docs'] as Map<dynamic, dynamic>;
    return docs.map(
      (final docId, final value) => MapEntry(
        docId as String,
        VersionVector.fromJson(Map<String, dynamic>.from(value)),
      ),
    );
  }

  static Map<String, Object?> delta({
    required final List<OpRecord> ops,
    required final List<Snapshot> states,
  }) => {
    'type': deltaType,
    'ops': [for (final op in ops) op.toJson()],
    'states': [for (final s in states) s.toJson()],
  };

  static ({List<OpRecord> ops, List<Snapshot> states}) parseDelta(
    final Object? raw,
  ) {
    final body = raw as Map<dynamic, dynamic>;
    return (
      ops: ((body['ops'] ?? const []) as List<dynamic>)
          .whereType<Map<dynamic, dynamic>>()
          .map((final e) => OpRecord.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      states: ((body['states'] ?? const []) as List<dynamic>)
          .whereType<Map<dynamic, dynamic>>()
          .map((final e) => Snapshot.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
