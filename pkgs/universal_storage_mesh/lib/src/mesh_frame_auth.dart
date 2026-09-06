import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'ephemeral_frame_auth.dart';

/// Ed25519-backed [EphemeralFrameSigner]: signs frames with this peer's
/// long-lived identity keypair — the exact material pairing issues via
/// `PairingService.newIdentityKeyPair()` (ADR 0010 §3, ADR 0031 §3). No
/// custom crypto is invented; every primitive comes from the pure-Dart
/// `cryptography` package.
final class MeshFrameSigner implements EphemeralFrameSigner {
  const MeshFrameSigner({required this.identityKeyPair});

  /// Long-lived Ed25519 identity keypair of the local peer.
  final SimpleKeyPair identityKeyPair;

  static final _ed25519 = Ed25519();

  @override
  Future<Uint8List> sign(final MeshEphemeralFrame frame) async {
    final signature = await _ed25519.sign(
      frame.signingInput(),
      keyPair: identityKeyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }
}

/// Ed25519-backed [EphemeralFrameAuthenticator] over the registry of
/// peer identity keys materialized by pairing (ADR 0031 §3). Hosts
/// register each paired peer's public key once; inbound frames are then
/// verified against the key registered for their claimed sender BEFORE
/// the tracker folds.
final class MeshFrameAuthenticator implements EphemeralFrameAuthenticator {
  MeshFrameAuthenticator({final Map<String, List<int>> identityKeys = const {}})
    : _identityKeys = {...identityKeys};

  /// peerId → Ed25519 public key bytes.
  final Map<String, List<int>> _identityKeys;

  static final _ed25519 = Ed25519();

  /// Peer id → Ed25519 public key bytes (read-only view).
  Map<String, List<int>> get identityKeys => Map.unmodifiable(_identityKeys);

  /// Registers [identityKey] as [peerId]'s identity key. Registration is
  /// a pairing outcome — never parsed from frame traffic.
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
    final identityKey = _identityKeys[frame.fromPeerId];
    // Shape guards before handing anything to the primitive: the Ed25519
    // verifier rejects malformed lengths with errors, not `false`.
    if (identityKey == null || identityKey.length != 32) return false;
    if (signature.length != 64) return false;
    return _ed25519.verify(
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
}
