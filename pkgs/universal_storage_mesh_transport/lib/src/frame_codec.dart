/// Length-prefixed message framing for stream transports (TCP, BLE
/// characteristic streams). The in-memory fake transport preserves message
/// boundaries natively and does not need this; real transports do.
library;

import 'dart:typed_data';

/// 4-byte big-endian length prefix + payload.
const int _lengthPrefixBytes = 4;
const int _maxFrameBytes = 8 * 1024 * 1024;

Uint8List frameMessage(final Uint8List payload) {
  final out = Uint8List(_lengthPrefixBytes + payload.length);
  final header = ByteData.view(
    out.buffer,
    out.offsetInBytes,
    _lengthPrefixBytes,
  );
  header.setUint32(0, payload.length);
  out.setAll(_lengthPrefixBytes, payload);
  return out;
}

/// Incremental de-framer: feed received bytes, get complete messages.
final class FrameDecoder {
  Uint8List _buffer = Uint8List(0);

  /// Extracts every complete frame from [bytes]; partial tails are retained.
  List<Uint8List> feed(final List<int> bytes) {
    final combined = Uint8List(_buffer.length + bytes.length)
      ..setRange(0, _buffer.length, _buffer)
      ..setRange(_buffer.length, _buffer.length + bytes.length, bytes);
    final frames = <Uint8List>[];
    var offset = 0;
    while (offset + _lengthPrefixBytes <= combined.length) {
      final length = ByteData.view(
        combined.buffer,
        combined.offsetInBytes + offset,
        _lengthPrefixBytes,
      ).getUint32(0);
      if (length > _maxFrameBytes) {
        throw ArgumentError('Frame of $length bytes exceeds $_maxFrameBytes');
      }
      if (offset + _lengthPrefixBytes + length > combined.length) break;
      frames.add(
        Uint8List.sublistView(
          combined,
          offset + _lengthPrefixBytes,
          offset + _lengthPrefixBytes + length,
        ),
      );
      offset += _lengthPrefixBytes + length;
    }
    _buffer = offset == combined.length
        ? Uint8List(0)
        : Uint8List.sublistView(combined, offset);
    return frames;
  }
}
