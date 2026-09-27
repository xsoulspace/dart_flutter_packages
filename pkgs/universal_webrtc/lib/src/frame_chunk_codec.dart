import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Wire envelope for frames crossing the sidecar's data channel.
///
/// Header (12 bytes, big endian): `u16 magic = 0x5853 ('XS')`,
/// `u8 type = 1 (frame)`, `u8 flags` (bit0 first chunk, bit1 last
/// chunk), `u32 sequence`, `u32 revision`; payload follows. Chunks are
/// at most 16 KiB so a message fits SCTP's conservative bound.
abstract final class FrameChunkCodec {
  /// Header size in bytes.
  static const int headerBytes = 12;

  /// `'XS'` marker.
  static const int magic = 0x5853;

  /// Frame payload type.
  static const int frameType = 1;

  /// First-chunk flag.
  static const int flagFirst = 1;

  /// Last-chunk flag.
  static const int flagLast = 2;

  /// Maximum payload bytes per chunk.
  static const int chunkPayloadLimit = 16 * 1024;

  /// Splits [payload] into wire chunks.
  static List<Uint8List> encode({
    required int sequence,
    required int revision,
    required Uint8List payload,
  }) {
    final chunkCount = (payload.length / chunkPayloadLimit).ceil();
    final chunks = List<Uint8List>.generate(chunkCount == 0 ? 1 : chunkCount, (
      index,
    ) {
      final start = index * chunkPayloadLimit;
      final end = (start + chunkPayloadLimit).min(payload.length);
      var flags = 0;
      if (index == 0) flags |= flagFirst;
      if (index == chunkCount - 1) flags |= flagLast;
      final header = ByteData(headerBytes)
        ..setUint16(0, magic)
        ..setUint8(2, frameType)
        ..setUint8(3, flags)
        ..setUint32(4, sequence)
        ..setUint32(8, revision);
      final chunk = Uint8List(headerBytes + end - start);
      chunk.setAll(0, header.buffer.asUint8List());
      chunk.setRange(headerBytes, chunk.length, payload, start);
      return chunk;
    });
    return chunks;
  }
}

extension _Min on int {
  int min(int other) => this < other ? this : other;
}

/// Reassembles chunked frames on the receiving side.
class FrameReassembler {
  Uint8List? _buffer;
  int _sequence = -1;
  int _revision = 0;

  /// Feeds one wire chunk; completes a frame when the last chunk lands.
  FrameFrameResult? accept(Uint8List chunk) {
    if (chunk.length < FrameChunkCodec.headerBytes) return null;
    final header = ByteData.sublistView(chunk);
    if (header.getUint16(0) != FrameChunkCodec.magic) return null;
    if (header.getUint8(2) != FrameChunkCodec.frameType) return null;
    final flags = header.getUint8(3);
    final sequence = header.getUint32(4);
    final revision = header.getUint32(8);
    final payload = chunk.sublist(FrameChunkCodec.headerBytes);
    if (flags & FrameChunkCodec.flagFirst != 0) {
      _buffer = payload;
      _sequence = sequence;
      _revision = revision;
    } else {
      _buffer = _buffer == null
          ? payload
          : (Uint8List.fromList([..._buffer!, ...payload]));
    }
    if (flags & FrameChunkCodec.flagLast != 0 && _buffer != null) {
      final frame = FrameFrameResult(
        sequence: _sequence,
        revision: _revision,
        bytes: _buffer!,
      );
      _buffer = null;
      return frame;
    }
    return null;
  }
}

/// A reassembled frame.
@immutable
class FrameFrameResult {
  /// Creates the result.
  const FrameFrameResult({
    required this.sequence,
    required this.revision,
    required this.bytes,
  });

  /// Frame sequence.
  final int sequence;

  /// Target revision.
  final int revision;

  /// Payload bytes.
  final Uint8List bytes;
}
