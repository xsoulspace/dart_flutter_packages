export 'mesh_kv_store_memory.dart' show MemoryMeshKvStore;

/// Platform-neutral persistence for mesh replica state (the peer registry
/// and convergence doc shards).
///
/// The concrete backing is selected at compile time via conditional import
/// (`mesh_kv_store_factory.dart` / `mesh_kv_store_web.dart` /
/// `mesh_kv_store_io.dart`):
///
/// - `dart:io` platforms (desktop/mobile): file-backed under the replica
///   root — the original on-disk layout is unchanged (`peers.json` plus
///   `docs/<shard>.json`).
/// - web (dart2js/DDC): browser `localStorage` namespaced by the requested
///   replica root, with an in-memory fallback when `localStorage` is
///   unavailable or throws. [MeshStorageConfig.storePath] is never used as
///   a filesystem path on web.
///
/// Keys are replica-relative POSIX-style paths such as `peers.json` or
/// `docs/<shard>.json`; implementations decide how they map to the backing
/// medium. Values are opaque JSON strings.
abstract interface class MeshKeyValueStore {
  /// Returns the value stored under [key], or `null` when absent.
  Future<String?> read(final String key);

  /// Writes [value] under [key], creating intermediate locations as
  /// needed (a no-op concern for non-file backings).
  Future<void> write(final String key, final String value);

  /// Returns all known keys starting with [prefix], sorted ascending.
  Future<List<String>> list(final String prefix);
}
