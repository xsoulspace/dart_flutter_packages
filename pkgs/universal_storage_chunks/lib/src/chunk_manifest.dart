import 'chunk_store.dart';

/// The kernel-doc VALUE describing one binary member (ADR 0042 §2).
///
/// An ordinary JSON-encodable map: it rides existing anti-entropy,
/// snapshots, compaction, and the LWW policy unchanged — binary LWW losers
/// keep their manifests staged through the existing conflict workflow,
/// recoverable, never silently destroyed. The kernel stays byte-blind:
/// ops carry manifests (small), never chunk payloads.
final class ChunkManifest {
  const ChunkManifest({
    required this.root,
    required this.size,
    required this.chunks,
    this.mime,
  });

  /// sha256 of the WHOLE content — verification anchor of a full
  /// materialization.
  final String root;

  /// Total byte size of the content.
  final int size;

  /// Ordered chunk addresses (sha256 of each chunk's uncompressed bytes).
  final List<String> chunks;

  /// Optional MIME hint for placeholder rendering.
  final String? mime;

  Map<String, Object?> toJson() => {
    'v': 1,
    'root': root,
    'size': size,
    'chunks': chunks,
    if (mime != null) 'mime': mime,
  };

  /// Null-safe decode (a malformed manifest is an absent manifest).
  static ChunkManifest? tryFromJson(final Object? raw) {
    if (raw is! Map) return null;
    final chunks = raw['chunks'];
    if (chunks is! List || raw['root'] is! String || raw['size'] is! int) {
      return null;
    }
    return ChunkManifest(
      root: raw['root'] as String,
      size: raw['size'] as int,
      chunks: chunks.whereType<String>().toList(),
      mime: raw['mime'] as String?,
    );
  }

  /// Addresses referenced but not present in [store].
  Future<List<String>> missingChunks(final ChunkStore store) async {
    final missing = <String>[];
    for (final address in chunks) {
      if (!await store.has(address)) missing.add(address);
    }
    return missing;
  }

  @override
  String toString() =>
      'ChunkManifest(root: ${root.substring(0, 12)}…, $size bytes, '
      '${chunks.length} chunks)';
}
