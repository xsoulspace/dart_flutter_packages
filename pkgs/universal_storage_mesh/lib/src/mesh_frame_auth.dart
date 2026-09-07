import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'ephemeral_frame_auth.dart';
import 'mesh_peer_registry.dart';

/// Ed25519-backed [EphemeralFrameSigner]: signs frames with this peer's
/// long-lived identity keypair — the exact material pairing issues via
/// `PairingService.newIdentityKeyPair()` (ADR 0010 §3, ADR 0031 §3). No
/// custom crypto is invented; every primitive comes from the pure-Dart
/// `cryptography` package.
///
/// By default the signer also PUBLISHES its public identity key with
/// every signed frame ([EphemeralFrameIdentityPublisher], payload-only
/// ride-along under [kIdentityKeyPayloadKey]) so trust-on-first-use
/// receivers can bind `peerId → key` on first contact — the fix for the
/// asymmetric v1 pairing posture where the host never learns the peer's
/// key out of band. Receivers with this signer's key already pinned
/// verify against the PIN and ignore the ride-along. Opt out with
/// [publishIdentityKey] `false` (frames stay signed but unlearnable).
final class MeshFrameSigner
    implements EphemeralFrameSigner, EphemeralFrameIdentityPublisher {
  MeshFrameSigner({
    required this.identityKeyPair,
    this.publishIdentityKey = true,
  });

  /// Long-lived Ed25519 identity keypair of the local peer.
  final SimpleKeyPair identityKeyPair;

  /// Whether signed frames carry this signer's public identity key as a
  /// payload ride-along (v1 relay-owned TOFU — see
  /// [MeshFrameAuthenticator]'s trust model).
  final bool publishIdentityKey;

  Future<List<int>?>? _identityKeyFuture;

  static final _ed25519 = Ed25519();

  @override
  Future<Uint8List> sign(final MeshEphemeralFrame frame) async {
    final signature = await _ed25519.sign(
      frame.signingInput(),
      keyPair: identityKeyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }

  @override
  Future<List<int>?> identityKeyForPayload() {
    if (!publishIdentityKey) return Future<List<int>?>.value();
    // Race-safe: concurrent callers share one extraction future.
    return _identityKeyFuture ??= identityKeyPair.extractPublicKey().then(
      (final key) => key.bytes,
    );
  }
}

/// Ed25519-backed [EphemeralFrameAuthenticator] over the registry of
/// peer identity keys materialized by pairing (ADR 0031 §3). Hosts
/// register each paired peer's public key once; inbound frames are then
/// verified against the key registered for their claimed sender BEFORE
/// the tracker folds.
///
/// ## v1 trust model — relay-owned TOFU with key pinning
///
/// Pairing is ASYMMETRIC in v1: the host advertises itself (prints the
/// signed pairing payload) and the PEER accepts
/// (`acceptPairingCode` → `registerPeer` on the peer side only). The
/// host therefore never learns the peer's identity key out of band — its
/// authenticator has no key for the peer, so the peer's signed frames
/// are dropped host-side and presence is dead on the host. The v1
/// posture fixes this with trust-on-first-use anchored in relay
/// ownership:
///
/// - A SIGNED frame from an UNKNOWN peer — no key pinned here, none
///   pre-shared via [registerIdentityKey]/[MeshPeerRegistry] — carries
///   the sender's public identity key in its payload ride-along
///   ([kIdentityKeyPayloadKey]). This is the wiring-level trust anchor:
///   the receiver's frame source is a relay the local device HOSTS (or
///   has paired with), and that relay is the paired host's own device.
///   The authenticator verifies the signature against the claimed key,
///   BINDS `peerId → key` on first contact, registers the peer record
///   into [peerRegistry] when one is attached, and folds the frame.
/// - Any LATER frame from the same peerId made with a DIFFERENT key
///   fails verification against the pinned key and is rejected as named
///   data — pins are immutable for the life of the process, and TOFU
///   never fires again for a bound peer.
/// - Pre-shared (paired) keys ALWAYS take precedence: TOFU never fires
///   for a peer whose key is already registered and never overwrites a
///   pin — `registerPeer`/peer-registry stays the source for
///   pre-shared keys.
/// - TOFU-learned keys persist WITH THE REPLICA when [peerRegistry] is
///   the replica-backed registry (file under `dart:io`,
///   `localStorage`-backed on web): the learned key lands in the peer
///   record, so a reload re-pins it before any frame arrives. A failed
///   registry write never blocks the fold — the in-process pin is
///   already authoritative.
///
/// This is honest v1: first contact is anchored in relay ownership, not
/// an out-of-band key exchange, so a first-contact impersonator that can
/// inject over the relay before the real peer's frame arrives could
/// hijack an unknown peerId (classic TOFU risk, accepted for v1 because
/// the relay is the paired host's own device). Pinning then makes every
/// later frame from that peerId name the pinned key as data or be
/// dropped.
///
/// OPEN QUESTION (not built): the upgrade path is a BIDIRECTIONAL
/// pairing exchange where the host learns the peer's identity key out of
/// band, retiring TOFU for pre-shared peers entirely.
final class MeshFrameAuthenticator implements EphemeralFrameAuthenticator {
  MeshFrameAuthenticator({
    final Map<String, List<int>> identityKeys = const {},
    this.trustOnFirstUse = true,
    this.peerRegistry,
  }) : _identityKeys = {...identityKeys};

  /// Whether an unknown peer's first verifiable signed frame binds
  /// `peerId → key` (v1 relay-owned TOFU — see the class trust model).
  /// `false` restores the strict pre-shared-only posture: unknown peers
  /// are rejected as named data even when perfectly signed.
  final bool trustOnFirstUse;

  /// Durable registry TOFU-learned keys are registered into. Attach the
  /// REPLICA-backed registry ([MeshPeerRegistry.loadFromStore] over the
  /// replica's [MeshKeyValueStore]) to persist learned keys with the
  /// replica — file-backed under `dart:io`, `localStorage`-backed on
  /// web. `null` keeps learned keys in-process only.
  final MeshPeerRegistry? peerRegistry;

  /// peerId → Ed25519 public key bytes. Pre-shared pins (pairing
  /// outcomes) and TOFU-learned bindings both live here; an entry is
  /// immutable once written.
  final Map<String, List<int>> _identityKeys;

  static final _ed25519 = Ed25519();

  /// Peer id → Ed25519 public key bytes (read-only view).
  Map<String, List<int>> get identityKeys => Map.unmodifiable(_identityKeys);

  /// Registers [identityKey] as [peerId]'s identity key. Registration is
  /// a pairing outcome — never parsed from frame traffic (TOFU bindings
  /// are the one exception, see the class trust model; they only ever
  /// fill a MISSING pin, never overwrite one).
  void registerIdentityKey({
    required final String peerId,
    required final List<int> identityKey,
  }) {
    _identityKeys[peerId] = List<int>.of(identityKey);
  }

  @override
  Future<bool> verify(final MeshEphemeralFrame frame) async {
    final signature = frame.signature;
    if (signature == null) return false;
    // Shape guards before handing anything to the primitive: the Ed25519
    // verifier rejects malformed lengths with errors, not `false`.
    if (signature.length != 64) return false;
    final pinned = _identityKeys[frame.fromPeerId];
    if (pinned != null) {
      // Pinned: verify against the registered key ONLY. A frame made
      // with any other key fails here and is dropped as named data —
      // the pin is immutable (key pinning, v1 trust model).
      if (pinned.length != 32) return false;
      return _verifyWithKey(frame, signature, pinned);
    }
    if (!trustOnFirstUse) return false;
    // Unknown peer: TOFU — bind on first contact (v1 trust model). The
    // claimed key comes from the payload ride-along; it is never
    // trusted before the signature verifies against it.
    final claimed = _claimedIdentityKey(frame);
    if (claimed == null || claimed.length != 32) return false;
    if (!await _verifyWithKey(frame, signature, claimed)) return false;
    await _bind(frame.fromPeerId, claimed);
    return true;
  }

  /// Base64-decodes the sender's claimed public identity key from the
  /// payload ride-along; `null` when absent or malformed. Opaque
  /// ride-along data — verification against it is the only thing that
  /// makes it meaningful.
  static List<int>? _claimedIdentityKey(final MeshEphemeralFrame frame) {
    final claimed = frame.payload[kIdentityKeyPayloadKey];
    if (claimed is! String || claimed.isEmpty) return null;
    try {
      return base64Decode(claimed);
    } on FormatException {
      return null;
    }
  }

  /// Verifies [frame]'s signature against [identityKey]. Errors from the
  /// primitive (malformed point material in an attacker-controlled
  /// claimed key, say) mean "not authentic", never "abort".
  Future<bool> _verifyWithKey(
    final MeshEphemeralFrame frame,
    final List<int> signature,
    final List<int> identityKey,
  ) async {
    try {
      return await _ed25519.verify(
        frame.signingInput(),
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(
            Uint8List.fromList(identityKey),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    }
    // The verifier signals malformed key/signature material with
    // `ArgumentError` — the same "not authentic" outcome as `false`
    // (mirrors [PairingService._verifySignature]).
    // ignore: avoid_catching_errors
    on ArgumentError {
      return false;
    }
  }

  /// Pins the learned binding and, when a registry is attached,
  /// registers the peer record so the key persists with the replica
  /// (v1 trust model). Fills a MISSING pin only — [verify] routes
  /// already-pinned peers through the pinned path, so a bind can never
  /// overwrite one.
  Future<void> _bind(final String peerId, final List<int> identityKey) async {
    _identityKeys[peerId] = List<int>.of(identityKey);
    final registry = peerRegistry;
    if (registry == null) return;
    final existing = registry.byId(peerId);
    try {
      await registry.register(
        existing == null
            ? MeshPeerRecord(
                peerId: peerId,
                displayName: peerId,
                identityKey: identityKey,
              )
            : MeshPeerRecord(
                peerId: existing.peerId,
                displayName: existing.displayName,
                endpointHints: existing.endpointHints,
                identityKey: identityKey,
              ),
      );
    } on Object catch (_) {
      // Persistence is best-effort: the in-process pin above is already
      // authoritative for this process; a failed write (unwritable
      // backing, quota) never blocks the fold.
    }
  }
}
