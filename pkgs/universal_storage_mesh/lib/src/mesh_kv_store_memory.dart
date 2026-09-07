/// Pure in-memory [MeshKeyValueStore].
///
/// Used as the web fallback when browser `localStorage` is unavailable,
/// and in tests simulating web-backed replicas (records live for the
/// process/session only; a fresh process starts an empty store).
library;

import 'mesh_kv_store.dart';

/// Ephemeral key-value store: records live for the owning session only.
final class MemoryMeshKvStore implements MeshKeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(final String key) async => _data[key];

  @override
  Future<void> write(final String key, final String value) async {
    _data[key] = value;
  }

  @override
  Future<List<String>> list(final String prefix) async {
    final keys = _data.keys.where((final key) => key.startsWith(prefix));
    return (keys.toList()..sort());
  }
}
