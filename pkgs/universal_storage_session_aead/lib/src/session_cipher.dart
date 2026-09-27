import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Wire-format constants of the `mesh-session/v1` channel (ADR 0039).
abstract final class SessionAeadProtocol {
  /// Protocol name bound into handshake signatures, KDF salt, and KDF info
  /// (sibling of `mesh-pair/v1` — cross-protocol signature confusion is
  /// impossible because every signing input starts with this name).
  static const name = 'mesh-session/v1';

  /// The only handshake wire version this package speaks; other versions
  /// are rejected before any key material is used.
  static const version = 1;

  /// The only sealed-record version this package speaks.
  static const recordVersion = 1;

  /// Poly1305 tag length (bytes).
  static const tagLength = 16;

  /// ChaCha20-Poly1305 nonce length (bytes).
  static const nonceLength = 12;

  /// Sealed-record header: 1 version byte + 8 sequence bytes (u64 LE).
  static const headerLength = 9;
}

/// Authenticated encryption over one session's two directions.
///
/// * `seal` — encrypts [plaintext] under the send key with a strictly
///   increasing per-direction sequence; the sequence rides the record
///   header and is bound as AAD, so header tampering breaks the tag.
/// * `open` — decrypts a record from the remote peer; returns `null` for
///   ANY failure (short record, unknown version, tampered tag, replayed or
///   reordered sequence) so callers drop it as named data — never fatal,
///   never folded.
///
/// Nonces never repeat under a key: session keys are freshly derived per
/// handshake and the 96-bit nonce is `0x00000000 || sequence (u64 LE)`,
/// with sequences monotonic per direction. Reflection is structurally
/// impossible — a frame sealed under the i→r key fails to open with the
/// r→i receive key.
///
/// Both operations are synchronous, pure Dart: the per-frame cost is the
/// actual cipher work on the calling isolate (measured ~50–100 µs for
/// pointer-sized frames on Apple Silicon — see `tool/benchmark.dart`), with
/// no microtask hops, so a 30 Hz sender can seal on the UI isolate.
final class SessionCipher {
  SessionCipher({required this.sendKey, required this.receiveKey});

  /// AEAD key for frames this side sends (i→r on the initiator, r→i on the
  /// responder).
  final SecretKeyData sendKey;

  /// AEAD key for frames this side receives.
  final SecretKeyData receiveKey;

  // The sync cipher type is not nameable through the public cryptography
  // exports — inference carries it.
  static final _sync = Chacha20.poly1305Aead().toSync();

  int _sendSequence = 0;

  int _receiveSequence = -1;

  /// Records sealed so far (the next record's sequence).
  int get sentCount => _sendSequence;

  /// Records opened successfully so far.
  int get receivedCount => _receiveSequence + 1;

  /// Seals [plaintext] into one wire record.
  Uint8List seal(final List<int> plaintext) {
    // Read-and-increment BEFORE any await-able work: callers may fire and
    // forget; the sequence must still be unique per record.
    final sequence = _sendSequence++;
    final header = _recordHeader(sequence);
    final secretBox = _sync.encryptSync(
      plaintext,
      secretKey: sendKey,
      nonce: _nonce(sequence),
      aad: header,
    );
    return Uint8List.fromList([
      ...header,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  /// Opens a sealed record; `null` when it is not authentic or not fresh.
  Uint8List? open(final Uint8List record) {
    if (record.length <
        SessionAeadProtocol.headerLength + SessionAeadProtocol.tagLength) {
      return null;
    }
    if (record[0] != SessionAeadProtocol.recordVersion) return null;
    final sequence = ByteData.sublistView(
      record,
      1,
      SessionAeadProtocol.headerLength,
    ).getUint64(0, Endian.little);
    // The transport seam delivers ordered bytes (ADR 0010 §1), so a
    // sequence at or below the last opened one is a replay — and a skipped
    // order would hide one. Drop as named data either way.
    if (sequence <= _receiveSequence) return null;
    final header = Uint8List.sublistView(
      record,
      0,
      SessionAeadProtocol.headerLength,
    );
    const bodyStart = SessionAeadProtocol.headerLength;
    final bodyEnd = record.length - SessionAeadProtocol.tagLength;
    try {
      final clearText = _sync.decryptSync(
        SecretBox(
          Uint8List.sublistView(record, bodyStart, bodyEnd),
          nonce: _nonce(sequence),
          mac: Mac(Uint8List.sublistView(record, bodyEnd)),
        ),
        secretKey: receiveKey,
        aad: header,
      );
      _receiveSequence = sequence;
      return Uint8List.fromList(clearText);
    }
    // A failed tag is the primitive signaling "not authentic" with an
    // error; both it and malformed material mean "drop the frame", never
    // "abort the stream" (mirrors MeshEphemeralFrame.tryDecode).
    // ignore: avoid_catching_errors
    on Object {
      return null;
    }
  }

  static Uint8List _recordHeader(final int sequence) {
    final header = Uint8List(SessionAeadProtocol.headerLength);
    header[0] = SessionAeadProtocol.recordVersion;
    ByteData.view(header.buffer).setUint64(1, sequence, Endian.little);
    return header;
  }

  /// 96-bit nonce `0x00000000 || sequence (u64 LE)` — unique per direction
  /// under the freshly derived session key.
  static Uint8List _nonce(final int sequence) {
    final nonce = Uint8List(SessionAeadProtocol.nonceLength);
    ByteData.view(nonce.buffer).setUint64(4, sequence, Endian.little);
    return nonce;
  }
}
