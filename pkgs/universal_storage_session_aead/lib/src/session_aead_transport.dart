import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'session_aead_session.dart';

/// Wraps any [MeshTransport] so every session it yields is a sealed
/// [SessionAeadSession] (ADR 0039) — ADR 0010 §1's confidentiality and
/// peer-authentication obligations, discharged once for all radios:
///
/// * [connect] dials the inner transport, then initiates the handshake as
///   initiator. The pin comes from `MeshPeerRecord.identityKey` first,
///   falling back to [pinnedIdentityKeys].
/// * [incoming] accepts each inbound session as responder in parallel —
///   one slow handshake never delays another peer's session.
///
/// Handshake failures never kill the streams: the raw session is closed,
/// [onHandshakeFailure] observes the error, and the next inbound session
/// is still accepted. [MeshConnectionException] from the inner transport
/// propagates unchanged (dialing failed before any crypto ran).
///
/// ```dart
/// final transport = SessionAeadTransport(
///   inner: webSocketTransport,
///   identityKeyPair: myIdentity,
///   selfId: 'device-a',
///   pinnedIdentityKeys: {'device-b': bIdentityKeyBytes},
/// );
/// final session = await transport.connect(peerRecordOfB); // sealed
/// ```
final class SessionAeadTransport implements MeshTransport {
  SessionAeadTransport({
    required this.inner,
    required this.identityKeyPair,
    required this.selfId,
    this.pinnedIdentityKeys = const {},
    this.trustOnFirstUse = false,
    this.onHandshakeFailure,
  });

  /// The plaintext transport being wrapped (LAN socket, relay, fake…).
  final MeshTransport inner;

  /// This peer's long-lived Ed25519 identity keypair (pairing material).
  final SimpleKeyPair identityKeyPair;

  /// This peer's stable id.
  final String selfId;

  /// peerId → Ed25519 public key pins (pairing outcomes). Pre-shared pins
  /// always take precedence over handshake ride-along keys.
  final Map<String, List<int>> pinnedIdentityKeys;

  /// Whether an unknown peer's first verifiable handshake binds
  /// `peerId → key` (learned key arrives via
  /// [SessionAeadSession.remoteIdentityKey]; the failure callback's
  /// session exposes it only on success). `false` rejects unknown peers
  /// strictly — the responder before revealing anything.
  final bool trustOnFirstUse;

  /// Observes failed inbound (and outbound) handshakes: `(raw session,
  /// error, stack trace)`. The raw session is already closed when this
  /// runs. Diagnostics seam — dropping the peer is the behavior either
  /// way (named data, never folded).
  final void Function(
    MeshSession raw,
    Object error,
    StackTrace stackTrace,
  )? onHandshakeFailure;

  final _incoming = StreamController<MeshSession>();

  StreamSubscription<MeshSession>? _innerSubscription;

  var _disposed = false;

  @override
  Future<MeshSession> connect(final MeshPeerRecord peer) async {
    final pinned = peer.identityKey.isNotEmpty
        ? peer.identityKey
        : pinnedIdentityKeys[peer.peerId];
    final raw = await inner.connect(peer);
    try {
      return await SessionAeadSession.start(
        raw: raw,
        identityKeyPair: identityKeyPair,
        selfId: selfId,
        remotePeerId: peer.peerId,
        expectedPeerIdentityKey: pinned,
        trustOnFirstUse: trustOnFirstUse,
      );
    } on Object catch (error, stackTrace) {
      onHandshakeFailure?.call(raw, error, stackTrace);
      await raw.close();
      rethrow;
    }
  }

  @override
  Stream<MeshSession> get incoming {
    // One subscription on the inner transport for the lifetime of the
    // wrapper; each raw session is accepted independently (parallel
    // handshakes) and only successful ones reach the returned stream.
    _innerSubscription ??= inner.incoming.listen(
      (final raw) => unawaited(_accept(raw)),
    );
    return _incoming.stream;
  }

  Future<void> _accept(final MeshSession raw) async {
    try {
      final session = await SessionAeadSession.accept(
        raw: raw,
        identityKeyPair: identityKeyPair,
        selfId: selfId,
        pinnedIdentityKeys: pinnedIdentityKeys,
        trustOnFirstUse: trustOnFirstUse,
      );
      if (_disposed) {
        await session.close();
        return;
      }
      _incoming.add(session);
    } on Object catch (error, stackTrace) {
      await raw.close();
      onHandshakeFailure?.call(raw, error, stackTrace);
    }
  }

  /// Stops accepting inbound sessions and closes the wrapper's streams.
  /// Open sessions stay open — close them individually.
  Future<void> dispose() async {
    _disposed = true;
    await _innerSubscription?.cancel();
    _innerSubscription = null;
    // On a no-listener controller the done event stays buffered and
    // close()'s future never completes — detach it (the streams' fates
    // after dispose are nobody's concern).
    unawaited(_incoming.close());
  }
}
