import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'session_cipher.dart';
import 'session_handshake.dart';

/// One authenticated, encrypted link over a raw [MeshSession] (ADR 0039).
///
/// `start` (initiator — the side that dialed) and `accept` (responder —
/// the side that received) run the 3-message handshake on [raw]'s byte
/// stream, then every later frame is ChaCha20-Poly1305 sealed (see
/// [SessionCipher]). The handshake authenticates BOTH peers against
/// pre-shared identity pins when available; [SessionAeadSession] exists
/// only after mutual authentication succeeded, so its bytes are always
/// from the verified peer and unreadable to anyone else.
///
/// Trust model mirrors `MeshFrameAuthenticator` (ADR 0031 §3):
///
/// * A PINNED key (pre-shared by pairing) is the only one tried for that
///   peer — the ride-along key in the handshake is ignored.
/// * An UNPINNED peer is accepted only when [SessionAeadSession.start] was
///   given `trustOnFirstUse` (or [SessionAeadSession.accept] was), and
///   only after the transcript signature verifies against the claimed
///   key. The learned key is returned via [remoteIdentityKey] so the
///   caller can pin it durably.
/// * Strict mode (`trustOnFirstUse: false`) rejects unknown peers before
///   revealing anything: the responder throws before its signed reply.
///
/// On the wire the handshake costs 2 Ed25519 signatures + 1 X25519 ECDH
/// ONCE per session (hundreds of milliseconds on Android debug — the same
/// as ONE per-frame signature today); every frame after that costs only
/// the AEAD. Fresh ephemerals per handshake give forward secrecy: a
/// compromised identity key cannot decrypt past sessions.
final class SessionAeadSession implements MeshSession {
  SessionAeadSession._(
    this._raw,
    this._cipher,
    this._wire,
    this.remotePeerId,
    this.remoteIdentityKey,
    this.trustedByPinnedKey,
  );

  /// Initiates the handshake on a session this side opened (the peer
  /// record dialed names [remotePeerId]).
  ///
  /// [expectedPeerIdentityKey] is the pre-shared pin (from
  /// `MeshPeerRecord.identityKey` or the caller's registry); when null,
  /// the peer's key is learned from the handshake ride-along — allowed
  /// only when [trustOnFirstUse] is true, and only after the transcript
  /// signature verifies against the claimed key.
  ///
  /// Throws [SessionHandshakeException] when the peer cannot be
  /// authenticated; the raw session is left for the caller to close (see
  /// [SessionAeadTransport.onHandshakeFailure] for the wrapper that does).
  static Future<SessionAeadSession> start({
    required final MeshSession raw,
    required final SimpleKeyPair identityKeyPair,
    required final String selfId,
    required final String remotePeerId,
    final List<int>? expectedPeerIdentityKey,
    final bool trustOnFirstUse = false,
  }) async {
    final wire = _Wire(raw);
    try {
      if (expectedPeerIdentityKey == null && !trustOnFirstUse) {
        throw SessionHandshakeException(
          'no pinned identity key for $remotePeerId and trustOnFirstUse '
          'is disabled',
        );
      }
      final ephemeral = await SessionHandshakeCodec.newEphemeralKeyPair();
      final ephPub = await ephemeral.extractPublicKey();
      final idPub = await identityKeyPair.extractPublicKey();
      final helloBody = SessionHello(
        ephemeralKey: Uint8List.fromList(ephPub.bytes),
        peerId: selfId,
        identityKey: Uint8List.fromList(idPub.bytes),
      ).encodeBody();
      await raw.send(helloBody);

      final replyBody = await wire.receive();
      final reply = SessionReply.parse(replyBody);
      // The pin binds (peerId, key) as a pair: a reply signed by the
      // pinned key but CLAIMING another peer id is an impersonation, not a
      // mismatch to tolerate.
      if (reply.hello.peerId != remotePeerId) {
        throw SessionHandshakeException(
          'reply claimed peer ${reply.hello.peerId}, expected $remotePeerId',
        );
      }
      final pinned = expectedPeerIdentityKey;
      final verifiedKey = pinned ?? reply.hello.identityKey;
      final learned = pinned == null;
      if (!await SessionHandshakeCodec.verify(
        role: SessionHandshakeRole.responder,
        helloBody: helloBody,
        replyBody: reply.unsignedBody,
        signature: reply.signature,
        identityKey: verifiedKey,
      )) {
        throw const SessionHandshakeException(
          'remote peer failed transcript verification',
        );
      }
      final cipher = await _deriveCipher(
        ephemeral: ephemeral,
        selfId: selfId,
        initiator: true,
        peerId: remotePeerId,
        peerEphemeralKey: reply.hello.ephemeralKey,
        helloBody: helloBody,
        replyBody: reply.unsignedBody,
      );
      final confirmation = await SessionHandshakeCodec.sign(
        role: SessionHandshakeRole.initiator,
        helloBody: helloBody,
        replyBody: reply.unsignedBody,
        identityKeyPair: identityKeyPair,
      );
      await raw.send(SessionConfirm(signature: confirmation).encode());
      wire.attach(cipher);
      return SessionAeadSession._(
        raw,
        cipher,
        wire,
        remotePeerId,
        Uint8List.fromList(verifiedKey),
        !learned,
      );
    } on Object {
      await wire.dispose();
      rethrow;
    }
  }

  /// Accepts the handshake on a session the remote peer opened. The
  /// claimed peer id comes off the wire; the caller's registry decides
  /// whether it is known.
  static Future<SessionAeadSession> accept({
    required final MeshSession raw,
    required final SimpleKeyPair identityKeyPair,
    required final String selfId,
    final Map<String, List<int>> pinnedIdentityKeys = const {},
    final bool trustOnFirstUse = false,
  }) async {
    final wire = _Wire(raw);
    try {
      final helloBody = await wire.receive();
      final hello = SessionHello.parse(helloBody);
      // A peer claiming OUR id is reflection or a misconfigured dialer;
      // both are protocol violations, never a session.
      if (hello.peerId == selfId) {
        throw SessionHandshakeException(
          'hello claims our own peer id ($selfId)',
        );
      }
      final pinned = pinnedIdentityKeys[hello.peerId];
      if (pinned == null && !trustOnFirstUse) {
        // Reject BEFORE the signed reply: a strict host reveals neither
        // identity nor ephemeral material to unknown peers.
        throw SessionHandshakeException(
          'unknown peer ${hello.peerId} and trustOnFirstUse is disabled',
        );
      }
      final ephemeral = await SessionHandshakeCodec.newEphemeralKeyPair();
      final ephPub = await ephemeral.extractPublicKey();
      final idPub = await identityKeyPair.extractPublicKey();
      final unsignedBody = SessionHello(
        ephemeralKey: Uint8List.fromList(ephPub.bytes),
        peerId: selfId,
        identityKey: Uint8List.fromList(idPub.bytes),
      ).encodeBody();
      final replySignature = await SessionHandshakeCodec.sign(
        role: SessionHandshakeRole.responder,
        helloBody: helloBody,
        replyBody: unsignedBody,
        identityKeyPair: identityKeyPair,
      );
      await raw.send(
        SessionReply.signed(
          unsignedBody: unsignedBody,
          signature: replySignature,
        ).encode(),
      );

      final confirmation = await wire.receive();
      final confirm = SessionConfirm.parse(confirmation);
      final verifiedKey = pinned ?? hello.identityKey;
      final learned = pinned == null;
      if (!await SessionHandshakeCodec.verify(
        role: SessionHandshakeRole.initiator,
        helloBody: helloBody,
        replyBody: unsignedBody,
        signature: confirm.signature,
        identityKey: verifiedKey,
      )) {
        // Field-diagnostic material: distinguishes a stale/foreign pin
        // (keyPrefix ≠ claimedKeyPrefix) from a transcript mismatch over the
        // SAME key (hello/reply byte counts differ between peers).
        final detail =
            'keyPrefix: ${_hex4(verifiedKey)}, '
            'claimedKeyPrefix: ${_hex4(hello.identityKey)}, '
            'helloBytes: ${helloBody.length}, '
            'replyBytes: ${unsignedBody.length}';
        throw SessionHandshakeException(
          'initiator failed transcript verification '
          '(againstPinnedKey: ${!learned}, $detail)',
        );
      }
      final cipher = await _deriveCipher(
        ephemeral: ephemeral,
        selfId: selfId,
        initiator: false,
        peerId: hello.peerId,
        peerEphemeralKey: hello.ephemeralKey,
        helloBody: helloBody,
        replyBody: unsignedBody,
      );
      wire.attach(cipher);
      return SessionAeadSession._(
        raw,
        cipher,
        wire,
        hello.peerId,
        Uint8List.fromList(verifiedKey),
        !learned,
      );
    } on Object {
      await wire.dispose();
      rethrow;
    }
  }

  static String _hex4(final List<int> bytes) => bytes
      .take(4)
      .map((final b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  static Future<SessionCipher> _deriveCipher({
    required final SimpleKeyPair ephemeral,
    required final String selfId,
    required final bool initiator,
    required final String peerId,
    required final Uint8List peerEphemeralKey,
    required final Uint8List helloBody,
    required final Uint8List replyBody,
  }) async {
    final shared = await SessionHandshakeCodec.sharedSecret(
      ownEphemeralKeyPair: ephemeral,
      peerEphemeralKey: peerEphemeralKey,
    );
    final keys = await SessionHandshakeCodec.deriveKeys(
      shared: shared,
      initiatorId: initiator ? selfId : peerId,
      responderId: initiator ? peerId : selfId,
      helloBody: helloBody,
      replyBody: replyBody,
    );
    return initiator
        ? SessionHandshakeCodec.initiatorCipher(keys)
        : SessionHandshakeCodec.responderCipher(keys);
  }

  final MeshSession _raw;

  final SessionCipher _cipher;

  final _Wire _wire;

  @override
  final String remotePeerId;

  /// The peer identity key this session was authenticated with — a
  /// pre-shared pin, or the TOFU-learned key when [trustedByPinnedKey] is
  /// false (callers should pin it durably, mirroring
  /// `MeshFrameAuthenticator`'s registry write).
  final Uint8List remoteIdentityKey;

  /// True when [remoteIdentityKey] was a pre-shared pin; false means the
  /// key was learned on this first contact (TOFU).
  final bool trustedByPinnedKey;

  /// Inbound frames that failed to open (tampered, replayed, reordered)
  /// — dropped as named data, never delivered.
  int get droppedInboundCount => _wire.dropped;

  @override
  Stream<Uint8List> get inbound => _wire.tail;

  @override
  Future<void> send(final Uint8List payload) =>
      _raw.send(_cipher.seal(payload));

  @override
  Future<void> close() async {
    await _wire.dispose();
    await _raw.close();
  }
}

/// Sole owner of the raw session's byte stream (a single-subscription
/// source: exactly one listen ever). During the handshake it delivers
/// messages to [receive]; afterwards it decrypts into the tail stream the
/// consumer of [SessionAeadSession.inbound] reads.
final class _Wire {
  _Wire(final MeshSession raw) {
    _subscription = raw.inbound.listen(
      (final bytes) {
        final cipher = _cipher;
        if (cipher == null) {
          final waiting = _waiting;
          if (waiting != null) {
            _waiting = null;
            waiting.complete(bytes);
          } else if (_pending.length < _pendingCapacity) {
            // A sealed frame racing the tail of the handshake (the peer
            // may send data the moment it finishes its side) — hold it in
            // order; attach() flushes. A bounded queue caps attacker
            // noise sent before any handshake message is due.
            _pending.add(bytes);
          } else {
            _dropped++;
          }
          return;
        }
        _openInto(cipher, bytes);
      },
      onDone: () {
        _closed = true;
        final waiting = _waiting;
        _waiting = null;
        waiting?.completeError(
          const SessionHandshakeException('session closed during handshake'),
        );
        if (!_tail.isClosed) unawaited(_tail.close());
      },
      onError: (final Object error) {
        final waiting = _waiting;
        _waiting = null;
        waiting?.completeError(error);
        if (!_tail.isClosed) _tail.addError(error);
      },
    );
  }

  /// Early sealed frames held while the handshake settles.
  static const _pendingCapacity = 64;

  late final StreamSubscription<Uint8List> _subscription;

  final StreamController<Uint8List> _tail = StreamController<Uint8List>();

  final List<Uint8List> _pending = <Uint8List>[];

  Completer<Uint8List>? _waiting;

  SessionCipher? _cipher;

  var _closed = false;

  int _dropped = 0;

  int get dropped => _dropped;

  Stream<Uint8List> get tail => _tail.stream;

  /// Receives the next raw handshake message. The handshake flow awaits
  /// at most one message at a time — concurrent calls are an internal
  /// contract violation. Messages that arrived before this call (the raw
  /// session may deliver while the acceptor is still winding up) are
  /// drained in order — the handshake message sequence is strict, so
  /// buffered bytes ARE the next message.
  Future<Uint8List> receive() {
    if (_closed) {
      return Future.error(
        const SessionHandshakeException('session closed during handshake'),
      );
    }
    if (_pending.isNotEmpty) {
      return Future<Uint8List>.value(_pending.removeAt(0));
    }
    final waiting = Completer<Uint8List>();
    _waiting = waiting;
    return waiting.future;
  }

  /// Switches the wire from handshake routing to decryption, replaying
  /// any frames that arrived before the cipher existed.
  void attach(final SessionCipher cipher) {
    _cipher = cipher;
    for (final bytes in List.of(_pending)) {
      _openInto(cipher, bytes);
    }
    _pending.clear();
  }

  void _openInto(final SessionCipher cipher, final Uint8List bytes) {
    final opened = cipher.open(bytes);
    if (opened == null) {
      _dropped++;
      return;
    }
    if (!_tail.isClosed) _tail.add(opened);
  }

  Future<void> dispose() async {
    _closed = true;
    await _subscription.cancel();
    if (!_tail.isClosed) unawaited(_tail.close());
  }
}
