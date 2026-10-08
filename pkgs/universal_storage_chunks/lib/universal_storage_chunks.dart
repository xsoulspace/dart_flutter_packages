/// Content-addressed chunk store for large binary members (ADR 0042).
///
/// Binaries become first-class world members without breaking the kernel:
/// bytes are cut by content-defined boundaries ([ContentDefinedChunker]),
/// addressed by sha256 ([ChunkStore] — immutable, additive, union-
/// commutative), and referenced from an ordinary kernel-doc value
/// ([ChunkManifest]) that rides the existing anti-entropy unchanged.
/// [ChunkedBlobStore] is the facade; [MeshChunkExchange] moves chunks over
/// a MeshSession with on-receipt hash verification (the wire form of
/// proof of possession: a chunk is only ever adopted when its bytes hash
/// to the requested address).
///
/// Progressive materialization ([ChunkedBlobStore.planProgressive]) is the
/// mip-streaming contract: leading chunks first, so a shell can render a
/// preview while the tail streams in — binary members get the same
/// "no loader" journey as text (ADR 0047 §5).
library;

export 'src/chunk_manifest.dart';
export 'src/chunk_store.dart';
export 'src/chunked_blob_store.dart';
export 'src/content_defined_chunker.dart';
export 'src/mesh_chunk_exchange.dart';
