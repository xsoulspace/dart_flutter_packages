import 'dart:typed_data';

import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Payload key the signer's public identity key rides under (base64
/// text) so trust-on-first-use receivers can bind `peerId → key` on
/// first contact (v1 relay-owned TOFU — see [MeshFrameAuthenticator]).
///
/// Payload-only by design: transports treat [MeshEphemeralFrame.payload]
/// as opaque JSON, so no envelope/wire change is needed. The key is
/// opaque ride-along data — it tells a TOFU receiver WHICH public key to
/// try; it never bypasses the signature check (the frame must verify
/// against the claimed key before any bind).
const kIdentityKeyPayloadKey = 'idk';

/// Signs ephemeral frames with the local peer's long-lived identity
/// keypair before they are sent (ADR 0031 §3).
///
/// Key material enters via this interface — the mesh package never
/// imports last_answer or platform keychains; pairing (ADR 0010 §3)
/// hands over an Ed25519 `SimpleKeyPair`-shaped keypair.
// A single-method SEAM — symmetric with [EphemeralFrameAuthenticator].
// ignore: one_member_abstracts
abstract interface class EphemeralFrameSigner {
  /// Returns the signature bytes over [frame]'s canonical signing input
  /// — `MeshEphemeralFrame.signingInput`:
  /// payload + fromPeerId + issuedAtMs.
  Future<Uint8List> sign(MeshEphemeralFrame frame);
}

/// Verifies inbound frames against the REGISTERED peer identity keys
/// before any fold (ADR 0031 §3). Unauthenticated or tampered frames are
/// dropped as named data by the caller — counted and reported, never
/// folded into presence state.
// A single-method SEAM — symmetric with [EphemeralFrameSigner].
// ignore: one_member_abstracts
abstract interface class EphemeralFrameAuthenticator {
  /// True when [frame] carries a signature made with the identity key
  /// registered for [MeshEphemeralFrame.fromPeerId]. False for unsigned
  /// frames, unknown peers, and failed verification alike — the caller
  /// drops without folding in every case.
  Future<bool> verify(MeshEphemeralFrame frame);
}

/// Optional capability of an [EphemeralFrameSigner]: publishing the
/// signer's public identity key alongside each signed frame so TOFU
/// receivers can bind `peerId → key` on first contact (v1 relay-owned
/// TOFU — see [MeshFrameAuthenticator]).
///
/// Publishing is additive and safe: receivers with the sender's key
/// already pinned verify against the PIN and ignore the ride-along; only
/// an unknown peer's key is ever learned, and only after the signature
/// verifies against it.
// A single-method SEAM — symmetric with [EphemeralFrameSigner].
// ignore: one_member_abstracts
abstract interface class EphemeralFrameIdentityPublisher {
  /// The signer's Ed25519 public identity key bytes (32) to ride in the
  /// outgoing frame payload under [kIdentityKeyPayloadKey]; `null` or an
  /// empty list publishes nothing (frames stay signed but unlearnable).
  Future<List<int>?> identityKeyForPayload();
}
