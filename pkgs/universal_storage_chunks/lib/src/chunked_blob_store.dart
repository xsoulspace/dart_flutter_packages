import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'chunk_store.dart';
import 'content_defined_chunker.dart';
import 'chunk_manifest.dart';

/// Thrown when a manifest references chunks no reachable store holds.
final class MissingChunksException implements Exception {
  MissingChunksException(this.addresses);

  final List<String> addresses;

  @override
  String toString() =>
      'MissingChunksException: ${addresses.length} chunk(s) missing, '
      'first: ${addresses.first}';
}

/// The blob facade (ADR 0042 §1 + §4): chunk → address → store → manifest.
///
/// A [ChunkManifest] is an ordinary kernel-doc value — store it in a
/// member's LWW register (via a [SingleFieldMemberCodec]-shaped op) and
/// the existing sync ships the reference; bytes move separately over the
/// [MeshChunkExchange] or any other channel.
final class ChunkedBlobStore {
  ChunkedBlobStore({required this.chunks, this.chunker = const ContentDefinedChunker()});

  /// The backing content-addressed store.
  final ChunkStore chunks;

  final ContentDefinedChunker chunker;

  /// Splits, stores (idempotently — dedupe is the address), and returns
  /// the manifest. v1 stores chunks uncompressed (ADR 0042 §1: the
  /// address never depends on the codec; compression is a later layer).
  Future<ChunkManifest> putBytes(
    final List<int> bytes, {
    final String? mime,
  }) async {
    final root = chunkAddress(bytes);
    final addresses = <String>[];
    for (final slice in chunker.chunk(bytes)) {
      final chunkBytes = bytes.sublist(slice.start, slice.end);
      final address = chunkAddress(chunkBytes);
      await chunks.put(chunkBytes, address: address);
      addresses.add(address);
    }
    return ChunkManifest(
      root: root,
      size: bytes.length,
      chunks: addresses,
      mime: mime,
    );
  }

  /// Materializes the whole content, verifying every chunk against its
  /// address and the result against [ChunkManifest.root]. Throws
  /// [MissingChunksException] when any chunk is unreachable.
  Future<Uint8List> getBytes(
    final ChunkManifest manifest, {
    final void Function(int materializedBytes)? onProgress,
  }) async {
    final missing = await manifest.missingChunks(chunks);
    if (missing.isNotEmpty) {
      throw MissingChunksException(missing);
    }
    final out = BytesBuilder(copy: false);
    var materialized = 0;
    for (final address in manifest.chunks) {
      final chunkBytes = (await chunks.get(address))!;
      out.add(chunkBytes);
      materialized += chunkBytes.length;
      onProgress?.call(materialized);
    }
    final bytes = out.toBytes();
    final root = chunkAddress(bytes);
    if (root != manifest.root) {
      throw StateError(
        'Chunk set does not reassemble to the manifest root '
        '(${manifest.root.substring(0, 12)}… != ${root.substring(0, 12)}…)',
      );
    }
    return bytes;
  }

  /// The mip-streaming plan (ADR 0047 §5): cumulative chunk prefixes,
  /// earliest first — step 0 is just the leading chunk (the preview),
  /// the last step is the whole content. A shell renders from catalog
  /// metadata + the first step while the tail streams in.
  ProgressivePlan planProgressive(final ChunkManifest manifest) {
    final plans = <List<String>>[];
    for (var i = 0; i < manifest.chunks.length; i++) {
      plans.add(manifest.chunks.sublist(0, i + 1));
    }
    return ProgressivePlan(manifest: manifest, chunkPrefixes: plans);
  }

  /// Conservative local-GC helper (ADR 0042 §4 v1): every chunk referenced
  /// by ANY of [manifests] — the reachable set. Anything NOT in here is a
  /// collection candidate after a grace period; this helper only computes,
  /// never deletes.
  Future<Set<String>> reachableAddresses(
    final Iterable<ChunkManifest> manifests,
  ) async {
    final reachable = <String>{};
    for (final manifest in manifests) {
      reachable.addAll(manifest.chunks);
    }
    return reachable;
  }
}

/// A progressive materialization ladder: [chunkPrefixes][i] lists the
/// chunks to materialize for step i (leading chunks first — meta, then
/// preview, then the tail).
@immutable
final class ProgressivePlan {
  const ProgressivePlan({required this.manifest, required this.chunkPrefixes});

  final ChunkManifest manifest;
  final List<List<String>> chunkPrefixes;

  /// Whether at least a leading prefix is a real preview (more than one
  /// step).
  bool get isProgressive => chunkPrefixes.length > 1;
}
