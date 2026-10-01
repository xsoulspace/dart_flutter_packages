/// Pluggable compression for definition-pack blocks.
///
/// The default is zlib via package:archive (native zlib on VM/Flutter,
/// pure-Dart Inflate/Deflate on web — see [ZLibBlockCodec]). The format
/// never assumes the algorithm: any runtime can inject its own
/// [BlockCodec] into both the builder and the reader, as long as both
/// sides agree.
abstract interface class BlockCodec {
  List<int> encode(final List<int> bytes);
  List<int> decode(final List<int> bytes);
}
