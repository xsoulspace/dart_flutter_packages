import 'dart:typed_data';

import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

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
