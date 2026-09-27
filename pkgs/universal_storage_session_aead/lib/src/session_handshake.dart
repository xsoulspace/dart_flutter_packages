import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import 'session_cipher.dart';

/// Raised when a `mesh-session/v1` handshake cannot be completed or
/// authenticated. Never carries key material. Treat as "do not use this
/// link" — no session keys exist (or they are discarded) whenever this
/// flies.
final class SessionHandshakeException implements Exception {
  const SessionHandshakeException(this.message);

  final String message;

  @override
  String toString() => 'SessionHandshakeException: $message';
}

/// Which side of the exchange a signature commits to. The role rides the
/// SIGNING INPUT (not the wire JSON), so a captured reply can never be
/// replayed as a confirmation or across protocols — the transcript prefix
/// would not match.
enum SessionHandshakeRole {
  initiator('initiator'),
  responder('responder');

  const SessionHandshakeRole(this.label);

  final String label;
}

/// Library-shared codec helpers (private, top level: the message classes
/// and [SessionHandshakeCodec] all use them).

Map<String, Object?> _decodeBody(final Uint8List body) {
  if (body.isEmpty) {
    throw const SessionHandshakeException('handshake message is empty');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(body));
    // ignore: avoid_catching_errors
  } on FormatException {
    throw const SessionHandshakeException(
      'handshake message is not valid JSON',
    );
  }
  if (decoded is! Map<Object?, Object?>) {
    throw const SessionHandshakeException(
      'handshake message is not a JSON object',
    );
  }
  final version = decoded['v'];
  if (version != SessionAeadProtocol.version) {
    throw SessionHandshakeException('unsupported handshake version: $version');
  }
  if (decoded['proto'] != SessionAeadProtocol.name) {
    throw const SessionHandshakeException(
      'handshake message carries a foreign protocol name',
    );
  }
  return Map<String, Object?>.from(decoded);
}

String _peerId(final Map<String, Object?> json) {
  final id = json['id'];
  if (id is! String || id.isEmpty) {
    throw const SessionHandshakeException('handshake message is missing id');
  }
  return id;
}

Uint8List _fixedKey(final Map<String, Object?> json, final String field) {
  final raw = json[field];
  if (raw is! String || raw.isEmpty) {
    throw SessionHandshakeException('handshake message is missing $field');
  }
  final decoded = _tryBase64(raw);
  if (decoded == null || decoded.length != 32) {
    throw SessionHandshakeException('$field is not 32 bytes');
  }
  return Uint8List.fromList(decoded);
}

Uint8List? _tryBase64(final String value) {
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

Uint8List _jsonBody(final Map<String, Object?> fields) =>
    Uint8List.fromList(utf8.encode(jsonEncode(fields)));

/// The initiator's hello (message 1) — also the unsigned body of the
/// responder's reply (message 2).
@immutable
final class SessionHello {
  const SessionHello({
    required this.ephemeralKey,
    required this.peerId,
    required this.identityKey,
  });

  /// Parses [body] (a received message 1, or the unsigned prefix of a
  /// message 2). Throws [SessionHandshakeException] on anything malformed —
  /// shape guards run BEFORE any signature check.
  factory SessionHello.parse(final Uint8List body) {
    final json = _decodeBody(body);
    return SessionHello(
      ephemeralKey: _fixedKey(json, 'e'),
      peerId: _peerId(json),
      identityKey: _fixedKey(json, 'idk'),
    );
  }

  /// Fresh X25519 ephemeral public key (32 bytes).
  final Uint8List ephemeralKey;

  /// Sender's stable peer id.
  final String peerId;

  /// Sender's long-lived Ed25519 public identity key (32 bytes) — the
  /// TOFU ride-along; pre-shared pins take precedence over it.
  final Uint8List identityKey;

  /// The exact body bytes to send (and to sign over — see
  /// [SessionHandshakeCodec.signatureInput]).
  Uint8List encodeBody() => _jsonBody({
    'v': SessionAeadProtocol.version,
    'proto': SessionAeadProtocol.name,
    'e': base64Encode(ephemeralKey),
    'id': peerId,
    'idk': base64Encode(identityKey),
  });

}

/// The responder's reply (message 2): a hello body with the responder's
/// Ed25519 transcript signature appended as the trailing 64 raw bytes —
/// the `mesh-pair/v1` payload layout. Appending (not embedding) is what
/// keeps the transcript byte-exact on both sides: the signature commits
/// to exactly the bytes preceding it, and the initiator verifies over
/// those received bytes as-is.
@immutable
final class SessionReply {
  SessionReply({required this.hello, required this.signature})
    : unsignedBody = hello.encodeBody();

  /// Assembles a reply from already-signed bytes (responder side — the
  /// signed body is reused verbatim, never re-encoded).
  factory SessionReply.signed({
    required final Uint8List unsignedBody,
    required final Uint8List signature,
  }) => SessionReply._(
    SessionHello.parse(unsignedBody),
    unsignedBody,
    signature,
  );

  const SessionReply._(this.hello, this.unsignedBody, this.signature);

  /// Parses received reply bytes; throws [SessionHandshakeException] when
  /// they are too short to carry a signature or the body is malformed.
  factory SessionReply.parse(final Uint8List bytes) {
    if (bytes.length <= _signatureLength) {
      throw const SessionHandshakeException(
        'reply is too short to carry a signature',
      );
    }
    final body = Uint8List.sublistView(
      bytes,
      0,
      bytes.length - _signatureLength,
    );
    final signature = Uint8List.sublistView(
      bytes,
      bytes.length - _signatureLength,
    );
    return SessionReply._(
      SessionHello.parse(body),
      Uint8List.fromList(body),
      Uint8List.fromList(signature),
    );
  }


  /// Responder identity + fresh ephemeral.
  final SessionHello hello;

  /// The exact unsigned body bytes (everything before the signature) —
  /// the transcript half both signatures and the key schedule commit to.
  final Uint8List unsignedBody;

  /// Ed25519 signature over the responder-role transcript (64 bytes).
  final Uint8List signature;

  static const _signatureLength = 64;

  Uint8List encode() =>
      Uint8List.fromList([...unsignedBody, ...signature]);
}

/// The initiator's confirmation (message 3) — the initiator's transcript
/// signature alone. The responder reconstructs the transcript from the
/// messages it already holds.
@immutable
final class SessionConfirm {
  const SessionConfirm({required this.signature});

  /// Parses received confirm bytes; throws [SessionHandshakeException]
  /// when the signature is missing or malformed.
  factory SessionConfirm.parse(final Uint8List bytes) {
    final json = _decodeBody(bytes);
    final signature = json['sig'];
    if (signature is! String || signature.isEmpty) {
      throw const SessionHandshakeException('confirm is missing a signature');
    }
    final decoded = _tryBase64(signature);
    if (decoded == null || decoded.length != 64) {
      throw const SessionHandshakeException(
        'confirm signature is not 64 bytes',
      );
    }
    return SessionConfirm(signature: decoded);
  }

  /// Ed25519 signature over the initiator-role transcript (64 bytes).
  final Uint8List signature;

  Uint8List encode() => _jsonBody({
    'v': SessionAeadProtocol.version,
    'proto': SessionAeadProtocol.name,
    'sig': base64Encode(signature),
  });

}

/// Directional session keys derived from the handshake. The okm split
/// mirrors `PairingService` (ADR 0010 §3): first half = responder→
/// initiator, second half = initiator→responder, so neither direction ever
/// encrypts under the other's key.
@immutable
final class SessionDirectionalKeys {
  const SessionDirectionalKeys({
    required this.responderToInitiator,
    required this.initiatorToResponder,
  });

  final Uint8List responderToInitiator;
  final Uint8List initiatorToResponder;
}

/// Pure `mesh-session/v1` codec and key schedule: message (de)serialization,
/// transcript signing inputs, and HKDF derivation. No streams, no state —
/// [SessionAeadSession] drives these over a raw session, tests exercise
/// them directly.
// A stateless utility class is all statics by design.
// ignore: avoid_classes_with_only_static_members
final class SessionHandshakeCodec {
  static final Ed25519 _ed25519 = Ed25519();
  static final X25519 _x25519 = X25519();
  static final Sha256 _sha256 = Sha256();
  static final Hkdf _kdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);

  /// Signs [transcript] with an Ed25519 [identityKeyPair]. Errors from the
  /// primitive mean "cannot sign" and propagate — signing failures are
  /// never silently converted to wire bytes.
  static Future<Uint8List> sign({
    required final SessionHandshakeRole role,
    required final Uint8List helloBody,
    required final Uint8List replyBody,
    required final SimpleKeyPair identityKeyPair,
  }) async {
    final signature = await _ed25519.sign(
      signatureInput(
        role: role,
        helloBody: helloBody,
        replyBody: replyBody,
      ),
      keyPair: identityKeyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }

  /// Verifies [signature] over a role transcript against [identityKey].
  /// Errors from the primitive (malformed point material in an
  /// attacker-chosen key) mean "not authentic", never "abort".
  static Future<bool> verify({
    required final SessionHandshakeRole role,
    required final Uint8List helloBody,
    required final Uint8List replyBody,
    required final Uint8List signature,
    required final List<int> identityKey,
  }) async {
    try {
      return await _ed25519.verify(
        signatureInput(
          role: role,
          helloBody: helloBody,
          replyBody: replyBody,
        ),
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(
            Uint8List.fromList(identityKey),
            type: KeyPairType.ed25519,
          ),
        ),
      );
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return false;
    }
  }

  /// Canonical transcript bytes a handshake signature commits to:
  /// `mesh-session/v1/<role>\n` + length-prefixed hello body +
  /// length-prefixed reply body. Length prefixes make the concatenation
  /// unambiguous; the protocol-name prefix makes cross-protocol replay
  /// (e.g. reusing a `mesh-pair/v1` signature) impossible.
  static Uint8List signatureInput({
    required final SessionHandshakeRole role,
    required final Uint8List helloBody,
    required final Uint8List replyBody,
  }) {
    final prefix = utf8.encode('${SessionAeadProtocol.name}/${role.label}\n');
    return Uint8List.fromList([
      ...prefix,
      ..._u32(helloBody.length),
      ...helloBody,
      ..._u32(replyBody.length),
      ...replyBody,
    ]);
  }

  /// Fresh X25519 ephemeral keypair — one per handshake, never reused
  /// (replay protection and forward secrecy both hang on this).
  static Future<SimpleKeyPair> newEphemeralKeyPair() => _x25519.newKeyPair();

  /// ECDH over the exchanged ephemerals.
  static Future<SecretKey> sharedSecret({
    required final SimpleKeyPair ownEphemeralKeyPair,
    required final Uint8List peerEphemeralKey,
  }) => _x25519.sharedSecretKey(
    keyPair: ownEphemeralKeyPair,
    remotePublicKey: SimplePublicKey(
      peerEphemeralKey,
      type: KeyPairType.x25519,
    ),
  );

  /// HKDF-SHA256 over the ECDH secret, bound to both peer ids (sorted, so
  /// both sides compute identical info — the PairingService convention)
  /// and the SHA-256 of the full transcript (channel binding: keys are
  /// welded to the exact authenticated bytes).
  static Future<SessionDirectionalKeys> deriveKeys({
    required final SecretKey shared,
    required final String initiatorId,
    required final String responderId,
    required final Uint8List helloBody,
    required final Uint8List replyBody,
  }) async {
    final transcript = await _sha256.hash(
      Uint8List.fromList([...helloBody, ...replyBody]),
    );
    final ids = [initiatorId, responderId]..sort();
    final info = '${SessionAeadProtocol.name}'
        '|${ids[0]}|${ids[1]}|'
        '${_hex(transcript.bytes)}';
    final derived = await _kdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode(SessionAeadProtocol.name),
      info: utf8.encode(info),
    );
    final okm = await derived.extractBytes();
    return SessionDirectionalKeys(
      responderToInitiator: Uint8List.fromList(okm.sublist(0, 32)),
      initiatorToResponder: Uint8List.fromList(okm.sublist(32, 64)),
    );
  }

  /// Cipher for the RESPONDER side (sends with the first okm half).
  static SessionCipher responderCipher(
    final SessionDirectionalKeys keys,
  ) => SessionCipher(
    sendKey: SecretKeyData(keys.responderToInitiator),
    receiveKey: SecretKeyData(keys.initiatorToResponder),
  );

  /// Cipher for the INITIATOR side (sends with the second okm half).
  static SessionCipher initiatorCipher(
    final SessionDirectionalKeys keys,
  ) => SessionCipher(
    sendKey: SecretKeyData(keys.initiatorToResponder),
    receiveKey: SecretKeyData(keys.responderToInitiator),
  );

  static Uint8List _u32(final int value) {
    final bytes = Uint8List(4);
    ByteData.view(bytes.buffer).setUint32(0, value, Endian.little);
    return bytes;
  }

  static String _hex(final List<int> bytes) => bytes
      .map((final b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}
