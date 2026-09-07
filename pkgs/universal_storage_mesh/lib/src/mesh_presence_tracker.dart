import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// One live presence entry for a peer on a document.
///
/// Derived data — a fold over unexpired kernel ephemeral ops (ADR 0029 §1).
/// It vanishes when the peer sends `leave` or when its last event's TTL
/// elapses; it is never persisted anywhere.
final class MeshPresenceEntry {
  const MeshPresenceEntry({
    required this.docId,
    required this.peerId,
    required this.lastEvent,
    required this.lastSeen,
    required this.expiresAt,
    this.details = const {},
  });

  final String docId;

  /// Stable id of the present peer.
  final String peerId;

  /// Last live event from the peer (`join` or `ping`; `leave` removes the
  /// entry entirely, it is never listed).
  final MeshEphemeralEvent lastEvent;

  /// Issuing HLC of the last observed event.
  final Hlc lastSeen;

  /// When this entry dies: issuing wall clock + event TTL.
  final DateTime expiresAt;

  /// Opaque event details carried by the frames (display name, cursors…),
  /// read from the register value's nested `details` map (ADR 0031 §6).
  final Map<String, Object?> details;

  @override
  String toString() =>
      'MeshPresenceEntry($peerId on $docId, $lastEvent until $expiresAt)';
}

/// AI-native half of dual-mode presence (ADR 0029 §1): feeds join / leave /
/// ping events into kernel ephemeral ops so "who is connected to this doc"
/// is a fold over live (unexpired) ephemeral ops — agent-queryable state,
/// not just UI state.
///
/// Division of labor:
/// - Transport frames ([MeshEphemeralFrame]) carry the events; they are
///   relayed like any other frame but are never persisted by any store
///   replica and never enter anti-entropy.
/// - Kernel ephemeral ops ([ConvergenceDoc.applyLocalEphemeral] locally,
///   `applyRemote(ops, now:)` for peers) hold the queryable state.
///
/// The tracker owns its own presence documents, fully separate from any
/// replica's durable docs: nothing it touches reaches a snapshot, the
/// durable version vector, or `MeshStorageProvider`'s store.
///
/// ```dart
/// final tracker = MeshPresenceTracker(actorId: 'device-a');
/// final frame = tracker.announce(
///   docId: 'doc/1', event: MeshEphemeralEvent.join,
/// );
/// await session.send(frame.encode()); // peers fold it via handleFrame
/// ```
final class MeshPresenceTracker {
  MeshPresenceTracker({
    required this.actorId,
    this.defaultTtl = const Duration(seconds: 30),
  });

  /// Stable id of the local peer; also the issuing actor of local
  /// ephemeral ops.
  final String actorId;

  /// TTL applied when a call does not pass one explicitly. Presence dies
  /// on disconnect by design (ADR 0029 §1): a peer that stops pinging
  /// expires out of the fold.
  final Duration defaultTtl;

  /// Register-value keys inside the per-peer LWW register value — one
  /// register per peer, so the latest event from a peer wins by HLC.
  ///
  /// Consumer payloads are NAMESPACED: they ride under the nested
  /// `_detailsKey` map (ADR 0031 §6), never flat beside the reserved
  /// keys — no key-coupling between the tracker and consumers, and no
  /// consumer payload can collide with one of these.
  static const _eventKey = 'event';
  static const _peerKey = 'peer';
  static const _ttlKey = 'ttl_ms';
  static const _detailsKey = 'details';

  final Map<String, ConvergenceDoc> _docs = {};

  /// Issues a local presence event, folds it locally via
  /// [ConvergenceDoc.applyLocalEphemeral], and returns the frame to send to
  /// peers (over any [MeshSession]; frames are opaque to transports).
  MeshEphemeralFrame announce({
    required final String docId,
    required final MeshEphemeralEvent event,
    final DateTime? now,
    final Duration? ttl,
    final Map<String, Object?> details = const {},
  }) {
    final effectiveTtl = ttl ?? defaultTtl;
    final at = now ?? DateTime.now();
    final doc = _docFor(docId);
    final op = doc.applyLocalEphemeral(
      _payload(
        peerId: actorId,
        event: event,
        ttl: effectiveTtl,
        details: details,
      ),
      at,
      ttl: effectiveTtl,
    );
    return MeshEphemeralFrame(
      docId: docId,
      fromPeerId: actorId,
      event: event,
      ttl: effectiveTtl,
      payload: {'op': op.toJson()},
      issuedAtMs: at.millisecondsSinceEpoch,
    );
  }

  /// Folds a frame received from a peer via `applyRemote(ops, now:)`.
  ///
  /// Returns false (state unchanged) when the frame is a local echo, does
  /// not carry a kernel ephemeral op, or carries one that does not match
  /// the frame (wrong doc, durable op, or forged actor). Redelivered
  /// frames are idempotent: the kernel dedupes by op id.
  bool handleFrame(final MeshEphemeralFrame frame, {final DateTime? now}) {
    if (frame.fromPeerId == actorId) return false;
    final raw = frame.payload['op'];
    if (raw is! Map) return false;
    final op = OpRecord.fromJson(Map<String, dynamic>.from(raw));
    if (op.docId != frame.docId) return false;
    // Durable ops must never ride ephemeral frames — they would smuggle
    // unlogged state into replicas that never persist it.
    if (op.ttl == null) return false;
    if (op.actorId != frame.fromPeerId) return false;
    _docFor(frame.docId).applyRemote([op], now: now);
    return true;
  }

  /// Live presence for [docId]: the fold over unexpired ephemeral ops.
  ///
  /// Pass [now] (the caller's clock) to sweep expired ops first and to
  /// filter entries whose TTL elapsed since the last sweep. Entries whose
  /// last event was `leave` are absent — the query answers "who is
  /// connected to this doc" right now.
  List<MeshPresenceEntry> presence(final String docId, {final DateTime? now}) {
    final doc = _docs[docId];
    if (doc == null) return const [];
    if (now != null) doc.sweepEphemeral(now);
    final entries = <MeshPresenceEntry>[];
    for (final entry in doc.ephemeralState.entries) {
      final parsed = _parseEntry(docId, entry.key, entry.value);
      if (parsed == null) continue;
      if (now != null && now.isAfter(parsed.expiresAt)) continue;
      entries.add(parsed);
    }
    entries.sort((final a, final b) => a.peerId.compareTo(b.peerId));
    return entries;
  }

  /// Drops expired ephemeral ops across every tracked document; returns
  /// how many were dropped. Expiry is commutative and idempotent (kernel
  /// contract, ADR 0029 §1).
  int sweep(final DateTime now) {
    var dropped = 0;
    for (final doc in _docs.values) {
      dropped += doc.sweepEphemeral(now);
    }
    return dropped;
  }

  // -- Internals -----------------------------------------------------------

  /// One dedicated kernel document per tracked doc id, ephemeral-only by
  /// usage: local events go through [applyLocalEphemeral], peer events
  /// through `applyRemote(ops, now:)` — neither ever touches durable state.
  ConvergenceDoc _docFor(final String docId) => _docs.putIfAbsent(
    docId,
    () => ConvergenceDoc(docId: docId, actorId: actorId),
  );

  Map<String, Object?> _payload({
    required final String peerId,
    required final MeshEphemeralEvent event,
    required final Duration ttl,
    required final Map<String, Object?> details,
  }) {
    // Consumer payloads live ONLY under the nested `details` map (ADR
    // 0031 §6 — wire shape taken before any consumer depended on the
    // flat form). Entries must be JSON-encodable: the register rides
    // inside the kernel op JSON on the frame.
    final value = <String, Object?>{
      _peerKey: peerId,
      _eventKey: event.name,
      _ttlKey: ttl.inMilliseconds,
      _detailsKey: Map<String, Object?>.of(details),
    };
    // `leave` tombstones the register so the peer drops out immediately;
    // the tombstone itself expires with the same TTL.
    if (event == MeshEphemeralEvent.leave) {
      return {'k': peerId, 'del': true, ...value};
    }
    return {'k': peerId, 'v': value};
  }

  MeshPresenceEntry? _parseEntry(
    final String docId,
    final String peerId,
    final Object? raw,
  ) {
    if (raw is! Map) return null;
    if (raw['del'] == true) return null; // Left: never listed as present.
    final value = raw['v'];
    if (value is! Map) return null;
    final hlcRaw = raw['hlc'];
    if (hlcRaw is! Map) return null;
    final hlc = Hlc.fromJson(Map<String, dynamic>.from(hlcRaw));
    final ttlMs = (value[_ttlKey] as num?)?.toInt();
    if (ttlMs == null) return null;
    MeshEphemeralEvent? event;
    for (final candidate in MeshEphemeralEvent.values) {
      if (candidate.name == value[_eventKey]) {
        event = candidate;
        break;
      }
    }
    if (event == null) return null;
    // Consumer payloads are read back from the nested `details` map (ADR
    // 0031 §6); a register without one carries no consumer payload.
    final rawDetails = value[_detailsKey];
    final details = rawDetails is Map
        ? Map<String, Object?>.from(rawDetails)
        : const <String, Object?>{};
    return MeshPresenceEntry(
      docId: docId,
      peerId: peerId,
      lastEvent: event,
      lastSeen: hlc,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        hlc.wallMillis,
      ).add(Duration(milliseconds: ttlMs)),
      details: details,
    );
  }
}
