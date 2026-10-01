import 'package:archive/archive.dart' as archive;

import 'block_codec.dart';

/// The default block codec: zlib, through package:archive — whose own
/// codec is platform-conditional (native dart:io zlib for performance,
/// pure-Dart Inflate/Deflate on web). One implementation works
/// everywhere, so packs built on the Mac decode in the browser and
/// vice versa.
///
/// The [BlockCodec] seam stays: a consumer can still inject a custom
/// codec; the FORMAT never assumes the algorithm — only that both
/// sides agree.
final class ZLibBlockCodec implements BlockCodec {
  const ZLibBlockCodec();

  @override
  List<int> encode(final List<int> bytes) =>
      const archive.ZLibEncoder().encodeBytes(bytes);

  @override
  List<int> decode(final List<int> bytes) =>
      const archive.ZLibDecoder().decodeBytes(bytes);
}
