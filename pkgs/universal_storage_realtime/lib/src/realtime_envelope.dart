import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The wire types every realtime session speaks (ADR 0050 §1). The two
/// control types never reach app callbacks and never claim authority.
abstract final class RealtimeTypes {
  /// Liveness ping, sent by BOTH ends of a link.
  static const heartbeat = 'heartbeat';

  /// The mandatory answer to a heartbeat.
  static const heartbeatAck = 'heartbeat-ack';

  /// An explicit "I stop driving" from the authoritative sender.
  static const releaseAll = 'release-all';

  static const reserved = <String>{heartbeat, heartbeatAck, releaseAll};

  /// Whether [type] is link control (never surfaced, never authoritative).
  static bool isReserved(final String type) => reserved.contains(type);
}

/// One realtime frame (ADR 0050 §2): a named app event with a delivery
/// class, sequence, timestamp, and an app-owned payload map.
///
/// - `rel: false` (droppable): newest-wins per type — a pointer stream
///   may drop intermediate frames under load, never queue them.
/// - `rel: true` (reliable): monotonic per-sender sequence, deduped on
///   receipt — pinch edges and key events must arrive exactly once.
///
/// The payload is deliberately app-owned (`Map<String, Object?>`): the
/// envelope defines DELIVERY, never schema — vosges's gesture vocabulary,
/// a game's input actions, a design tool's cursor stream are all just
/// payloads.
@immutable
final class RealtimeEnvelope {
  const RealtimeEnvelope({
    required this.type,
    required this.seq,
    required this.reliable,
    required this.issuedAtMs,
    this.payload = const <String, Object?>{},
  });

  /// The app event name (reserved control types excepted).
  final String type;

  /// Reliable: monotonic per sender. Droppable: per-type newest-wins
  /// counter (diagnostic only on the wire).
  final int seq;

  /// The delivery class (see the class doc).
  final bool reliable;

  /// Sender wall-clock at issue (ms epoch) — jitter/latency telemetry.
  final int issuedAtMs;

  /// The app-owned event body.
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'rt': 1,
    'type': type,
    'seq': seq,
    'rel': reliable,
    'ts': issuedAtMs,
    if (payload.isNotEmpty) 'payload': payload,
  };

  /// Strict decode: null unless the bytes carry the realtime marker.
  static RealtimeEnvelope? tryDecode(final Uint8List bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map || decoded['rt'] != 1) return null;
      final type = decoded['type'];
      final seq = decoded['seq'];
      if (type is! String || type.isEmpty || seq is! int) return null;
      final payload = decoded['payload'];
      return RealtimeEnvelope(
        type: type,
        seq: seq,
        reliable: decoded['rel'] == true,
        issuedAtMs: decoded['ts'] is int ? decoded['ts'] as int : 0,
        payload: payload is Map
            ? Map<String, Object?>.from(payload)
            : const <String, Object?>{},
      );
    } on FormatException {
      return null;
    }
  }

  Uint8List encode() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
}

/// Byte-level plane classifier (ADR 0047 "one server, two planes"):
/// whether a first inbound frame declares the REALTIME plane.
bool looksLikeRealtimeFrame(final Uint8List frame) {
  try {
    final decoded = jsonDecode(utf8.decode(frame));
    return decoded is Map && decoded['rt'] == 1;
  } on FormatException {
    return false;
  }
}
