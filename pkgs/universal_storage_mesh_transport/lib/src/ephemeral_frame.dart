import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Kind of an unlogged peer event carried by a [MeshEphemeralFrame]
/// (ADR 0029 §1: transport-level ephemeral frames stay OUT of the kernel —
/// unlogged, no durability, no GC).
enum MeshEphemeralEvent {
  /// A peer announced it is connected to the doc.
  join,

  /// A peer announced it is disconnecting from the doc.
  leave,

  /// A peer refreshed its liveness for the doc.
  ping;

  static MeshEphemeralEvent fromName(final String value) =>
      switch (value) {
        'join' => MeshEphemeralEvent.join,
        'leave' => MeshEphemeralEvent.leave,
        'ping' => MeshEphemeralEvent.ping,
        _ => throw ArgumentError.value(value, 'value', 'Unknown event kind'),
      };
}

/// One transport-level ephemeral frame: a peer event that is relayed like
/// any other frame but is NEVER persisted by a store replica and NEVER
/// enters anti-entropy (ADR 0029 §1). Presence carried this way dies on
/// disconnect by design.
///
/// The transport layer knows nothing about documents or convergence: the
/// [payload] is opaque JSON-encodable data for consumers (the presence
/// tracker in `universal_storage_mesh` carries the kernel op JSON under
/// its own key). Relays must not persist frames; they exist only in
/// transit and in the (volatile) fold of whoever consumes them.
@immutable
final class MeshEphemeralFrame {
  const MeshEphemeralFrame({
    required this.docId,
    required this.fromPeerId,
    required this.event,
    required this.ttl,
    this.payload = const <String, Object?>{},
    this.issuedAtMs,
  });

  factory MeshEphemeralFrame.fromJson(final Map<String, dynamic> json) =>
      MeshEphemeralFrame(
        docId: json['doc_id'] as String,
        fromPeerId: json['from_peer_id'] as String,
        event: MeshEphemeralEvent.fromName(json['event'] as String),
        ttl: Duration(milliseconds: (json['ttl_ms'] as num).toInt()),
        payload:
            json['payload'] == null
                ? const <String, Object?>{}
                : Map<String, Object?>.from(
                  json['payload'] as Map<dynamic, dynamic>,
                ),
        issuedAtMs: (json['issued_at_ms'] as num?)?.toInt(),
      );

  /// Restores a frame from [encode] bytes.
  factory MeshEphemeralFrame.decode(final List<int> bytes) {
    final raw = jsonDecode(utf8.decode(bytes)) as Map<dynamic, dynamic>;
    if (raw['v'] != MeshEphemeralFrameCodec.version) {
      throw ArgumentError('Unsupported ephemeral frame: ${raw['v']}');
    }
    return MeshEphemeralFrame.fromJson(
      Map<String, dynamic>.from(raw)..remove('v'),
    );
  }

  /// Document (or channel) the event refers to. Opaque to transports.
  final String docId;

  /// Stable id of the issuing peer.
  final String fromPeerId;

  final MeshEphemeralEvent event;

  /// How long the event stays meaningful; consumers drop the frame (and
  /// any state folded from it) once past `issuedAtMs + ttl`. A peer that
  /// stops pinging expires out of every fold without an explicit leave.
  final Duration ttl;

  /// Opaque, JSON-encodable event data (display names, cursors, and the
  /// kernel op JSON used by the presence tracker).
  final Map<String, Object?> payload;

  /// Issuing peer's wall-clock timestamp in epoch milliseconds, when the
  /// issuer chooses to expose it; `null` means "no frame-level claim" —
  /// expiry is then the consumer's concern (the kernel op carries its own
  /// HLC wall clock).
  final int? issuedAtMs;

  /// Serializes to bytes that ride any [MeshSession] unchanged.
  Uint8List encode() {
    final body = {
      'v': MeshEphemeralFrameCodec.version,
      'doc_id': docId,
      'from_peer_id': fromPeerId,
      'event': event.name,
      'payload': payload,
      'ttl_ms': ttl.inMilliseconds,
      if (issuedAtMs != null) 'issued_at_ms': issuedAtMs,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  /// True once [ttl] has elapsed relative to [now]; requires [issuedAtMs].
  bool isExpiredAt(final DateTime now) {
    final issued = issuedAtMs;
    if (issued == null) return false;
    return now.millisecondsSinceEpoch > issued + ttl.inMilliseconds;
  }

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      (other is MeshEphemeralFrame &&
          other.docId == docId &&
          other.fromPeerId == fromPeerId &&
          other.event == event &&
          other.ttl == ttl &&
          other.issuedAtMs == issuedAtMs &&
          _mapsEqual(other.payload, payload));

  @override
  int get hashCode => Object.hash(docId, fromPeerId, event, ttl, issuedAtMs);

  @override
  String toString() =>
      'MeshEphemeralFrame($event from $fromPeerId on $docId)';

  static bool _mapsEqual(final Map<String, Object?> a, final Map b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}

/// Wire-format constants for [MeshEphemeralFrame].
abstract final class MeshEphemeralFrameCodec {
  /// Bump on any wire-breaking change; [MeshEphemeralFrame.decode] rejects
  /// unknown versions instead of misreading a peer's event.
  static const version = 1;
}
