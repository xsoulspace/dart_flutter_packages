import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// Result of a completed pairing handshake: the peer's verified identity
/// plus the derived session keys (ADR 0010 §3).
///
/// Both sides of the handshake produce an equivalent [PairingResult]; the
/// session keys are identical, the identity key is each side's own.
@immutable
final class PairingResult {
  const PairingResult({
    required this.peerId,
    required this.peerIdentityKey,
    required this.sendKey,
    required this.receiveKey,
  });

  /// Stable id announced by the peer in its signed envelope.
  final String peerId;

  /// Ed25519 public key bytes of the peer (32 bytes).
  final Uint8List peerIdentityKey;

  /// AEAD key for frames we send to the peer.
  final SecretKey sendKey;

  /// AEAD key for frames we receive from the peer.
  final SecretKey receiveKey;
}

/// Out-of-band trust bootstrap (ADR 0010 §3).
///
/// The QR payload is `mesh-pair/v1`: the advertiser's stable peer id and
/// X25519 ephemeral key, signed with its long-lived Ed25519 identity key.
/// Scanning verifies the signature and completes an X25519 → HKDF key
/// exchange over the discovered transport; the QR scan itself is the
/// authenticator — no password, no PKI.
///
/// All primitives come from the pure-Dart `cryptography` package. No custom
/// crypto is invented here.
final class PairingService {
  static const _protocolName = 'mesh-pair/v1';
  static final _ed25519 = Ed25519();
  static final _x25519 = X25519();

  static final _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);

  /// Long-lived device identity key pair. Persist the extracted bytes
  /// securely; reuse across pairings so peers can recognize this device.
  static Future<SimpleKeyPair> newIdentityKeyPair() => _ed25519.newKeyPair();

  /// Builds the signed pairing payload to embed in a QR code.
  ///
  /// [ephemeralKeyPair] must be freshly generated per pairing (X25519).
  static Future<Uint8List> buildQrPayload({
    required final SimpleKeyPair identityKeyPair,
    required final SimpleKeyPair ephemeralKeyPair,
    required final String peerId,
    final String? transportHint,
  }) async {
    final ephPub = await ephemeralKeyPair.extractPublicKey();
    final identityPub = await identityKeyPair.extractPublicKey();
    final body = utf8.encode(
      jsonEncode({
        'v': 1,
        'peer_id': peerId,
        'eph': base64Encode(ephPub.bytes),
        'idk': base64Encode(identityPub.bytes),
      }),
    );
    final signature = await _ed25519.sign(body, keyPair: identityKeyPair);
    return Uint8List.fromList([
      ...utf8.encode('$_protocolName\n'),
      ...body,
      ...signature.bytes,
    ]);
  }

  /// Verifies a scanned [qrPayload] against the peer's known
  /// [peerIdentityKey] and derives session keys from both ephemeral keys.
  ///
  /// Throws [PairingException] when the signature is invalid or the payload
  /// is malformed — treat as "do not pair", never as a soft warning.
  ///
  /// [ownEphemeralKeyPair] is our fresh X25519 key pair for this pairing;
  /// [ourPeerId] is announced back to the peer inside the encrypted channel
  /// (not part of the QR itself).
  static Future<PairingResult> acceptQrPayload({
    required final Uint8List qrPayload,
    required final Uint8List peerIdentityKey,
    required final SimpleKeyPair ownEphemeralKeyPair,
    required final String ourPeerId,
  }) async {
    final parsed = _parsePayload(qrPayload);
    if (!await _verifySignature(
      parsed.body,
      parsed.signature,
      peerIdentityKey,
    )) {
      throw const PairingException('QR signature verification failed');
    }
    final Map<String, Object?> envelope;
    try {
      envelope = Map<String, Object?>.from(
        jsonDecode(utf8.decode(parsed.body)),
      );
    } on FormatException {
      throw const PairingException('Malformed pairing envelope');
    }
    if (envelope['v'] != 1) {
      throw PairingException('Unsupported pairing version: ${envelope['v']}');
    }
    final peerId = envelope['peer_id'] as String?;
    final ephRaw = envelope['eph'] as String?;
    if (peerId == null || peerId.isEmpty || ephRaw == null) {
      throw const PairingException('Missing peer_id or ephemeral key');
    }
    final peerEphemeral = SimplePublicKey(
      base64Decode(ephRaw),
      type: KeyPairType.x25519,
    );

    // X25519 ECDH → HKDF → two directional AEAD keys.
    final shared = await _x25519.sharedSecretKey(
      keyPair: ownEphemeralKeyPair,
      remotePublicKey: peerEphemeral,
    );
    final derived = await _kdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(_protocolName),
      info: _kdfInfo(ourPeerId, peerId),
    );
    final bytes = await derived.extractBytes();
    return PairingResult(
      peerId: peerId,
      peerIdentityKey: Uint8List.fromList(peerIdentityKey),
      // Responder side: sends with the first half, receives with the
      // second. The initiator mirrors this (see [deriveInitiatorKeys]).
      sendKey: SecretKey(bytes.sublist(0, 32)),
      receiveKey: SecretKey(bytes.sublist(32)),
    );
  }

  /// Derives the initiator-side keys after the responder's ephemeral
  /// public key arrives back over the session. Mirrors [acceptQrPayload]
  /// with roles swapped so both sides compute identical directional keys.
  static Future<PairingResult> deriveInitiatorKeys({
    required final SimpleKeyPair identityKeyPair,
    required final SimpleKeyPair ownEphemeralKeyPair,
    required final Uint8List peerEphemeralPublic,
    required final String ourPeerId,
    required final String peerId,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: ownEphemeralKeyPair,
      remotePublicKey: SimplePublicKey(
        peerEphemeralPublic,
        type: KeyPairType.x25519,
      ),
    );
    final derived = await _kdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(_protocolName),
      info: _kdfInfo(ourPeerId, peerId),
    );
    final bytes = await derived.extractBytes();
    return PairingResult(
      peerId: peerId,
      peerIdentityKey: Uint8List.fromList(
        (await identityKeyPair.extractPublicKey()).bytes,
      ),
      // Initiator side: sends with the second half, receives with the
      // first — the mirror of the responder's assignment.
      sendKey: SecretKey(bytes.sublist(32)),
      receiveKey: SecretKey(bytes.sublist(0, 32)),
    );
  }

  /// Canonical HKDF info string. Both sides must derive the SAME key
  /// material, so the two peer ids are sorted lexicographically — the
  /// result is identical regardless of which side computes it.
  static List<int> _kdfInfo(final String a, final String b) {
    final ids = [a, b]..sort();
    return utf8.encode('$_protocolName|${ids[0]}|${ids[1]}');
  }

  static ({List<int> body, List<int> signature}) _parsePayload(
    final Uint8List raw,
  ) {
    final prefix = utf8.encode('$_protocolName\n');
    if (raw.length < prefix.length + 2) {
      throw const PairingException('Payload too short');
    }
    for (var i = 0; i < prefix.length; i++) {
      if (raw[i] != prefix[i]) {
        throw const PairingException('Unknown protocol prefix');
      }
    }
    // Signature is the last 64 bytes (Ed25519).
    const sigLen = 64;
    if (raw.length < prefix.length + sigLen) {
      throw const PairingException('Payload missing signature');
    }
    return (
      body: raw.sublist(prefix.length, raw.length - sigLen),
      signature: raw.sublist(raw.length - sigLen),
    );
  }

  static Future<bool> _verifySignature(
    final List<int> body,
    final List<int> signature,
    final Uint8List identityKey,
  ) async {
    try {
      return await _ed25519.verify(
        body,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(identityKey, type: KeyPairType.ed25519),
        ),
      );
    } on ArgumentError {
      return false;
    }
  }
}

/// Raised when pairing fails structurally or cryptographically.
final class PairingException implements Exception {
  const PairingException(this.message);
  final String message;

  @override
  String toString() => 'PairingException: $message';
}
