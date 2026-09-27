/// Session encryption for Universal Storage mesh links (ADR 0039).
///
/// ADR 0010 §1 makes confidentiality and peer authentication
/// transport-level obligations: real transports must establish session keys
/// from pairing material before delivering any inbound bytes. This package
/// fulfills that obligation for any [MeshTransport]:
///
/// * [SessionAeadProtocol] — the `mesh-session/v1` wire constants.
/// * [SessionCipher] — ChaCha20-Poly1305 seal/open over one direction pair,
///   with strict sequence numbers (replays and reorders are dropped as
///   named data).
/// * [SessionAeadSession] — one authenticated link over a raw
///   [MeshSession]: a Noise-shaped 3-message handshake (fresh X25519
///   ephemerals, both sides Ed25519-sign the transcript with their
///   long-lived pairing identity keys) derives directional session keys,
///   then every frame is sealed. Frames are never signed per-frame: the
///   AEAD tag authenticates them.
/// * [SessionAeadTransport] — wraps any [MeshTransport] so `connect`
///   initiates and `incoming` accepts sealed sessions automatically.
///
/// Trust model mirrors `MeshFrameAuthenticator` (ADR 0031 §3): pre-shared
/// (paired) identity keys take precedence; `trustOnFirstUse` learns an
/// unknown peer's key on first verifiable contact only.
library;

export 'src/session_aead_session.dart';
export 'src/session_aead_transport.dart';
export 'src/session_cipher.dart';
export 'src/session_handshake.dart';
