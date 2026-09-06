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
///
/// ## Frame authentication (ADR 0031 §3)
///
/// A frame may carry a [signature] over (payload + fromPeerId +
/// issuedAtMs) — the canonical bytes are [signingInput] — made with the
/// issuing peer's long-lived identity keypair (the material pairing
/// issues, ADR 0010 §3). Receivers verify against the REGISTERED peer
/// identity keys before folding; unauthenticated or tampered frames are
/// dropped as named data and never folded. The signature is opaque here:
/// key material and algorithms enter via interfaces in the consuming
/// package, never via platform keychains.
@immutable
final class MeshEphemeralFrame {
  const MeshEphemeralFrame({
    required this.docId,
    required this.fromPeerId,
    required this.event,
    required this.ttl,
    this.payload = const <String, Object?>{},
    this.issuedAtMs,
    this.signature,
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
        signature:
            json['sig'] == null
                ? null
                : Uint8List.fromList(base64Decode(json['sig'] as String)),
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

  /// Signature over [signingInput] made with the issuing peer's identity
  /// keypair (ADR 0031 §3); `null` on unsigned frames. Opaque bytes —
  /// verification happens against registered peer identity keys in the
  /// consuming package, before any fold.
  final Uint8List? signature;

  /// Canonical bytes a signature commits to: a JSON document holding
  /// exactly (payload + fromPeerId + issuedAtMs) — the triple ADR 0031
  /// §3 authenticates. The wrapping object makes the concatenation
  /// unambiguous; [payload] must JSON round-trip identically on the
  /// receiving side, which [encode]/[decode] guarantee.
  Uint8List signingInput() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'payload': payload,
        'from_peer_id': fromPeerId,
        'issued_at_ms': issuedAtMs,
      }),
    ),
  );

  /// Returns a copy of this frame carrying [signature] (ADR 0031 §3:
  /// sign, then send).
  MeshEphemeralFrame withSignature(final Uint8List signature) =>
      MeshEphemeralFrame(
        docId: docId,
        fromPeerId: fromPeerId,
        event: event,
        ttl: ttl,
        payload: payload,
        issuedAtMs: issuedAtMs,
        signature: signature,
      );

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
      if (signature != null) 'sig': base64Encode(signature!),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  /// Decodes [bytes], returning `null` instead of throwing when they are
  /// not a decodable frame of this codec version (garbage, non-JSON, or
  /// an unknown version). Transports use this to skip bytes that were
  /// never ephemeral frames — malformed traffic is ignored, never fatal.
  static MeshEphemeralFrame? tryDecode(final List<int> bytes) {
    try {
      return MeshEphemeralFrame.decode(bytes);
    }
    // `decode` signals malformed input with exceptions AND errors
    // (FormatException, ArgumentError for unknown versions); both mean
    // "not a frame of this version", never "abort the stream".
    // ignore: avoid_catching_errors
    on Object {
      return null;
    }
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
          _mapsEqual(other.payload, payload) &&
          _bytesEqual(other.signature, signature));

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

  static bool _bytesEqual(final List<int>? a, final List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Wire-format constants for [MeshEphemeralFrame].
abstract final class MeshEphemeralFrameCodec {
  /// Bump on any wire-breaking change; [MeshEphemeralFrame.decode] rejects
  /// unknown versions instead of misreading a peer's event.
  ///
  /// The `sig` field (ADR 0031 §3) is additive: version 1 decoders ignore
  /// unknown keys, and unsigned frames stay decodable — they simply fail
  /// authentication at any receiver that enforces ADR 0031 §3.
  static const version = 1;
}
