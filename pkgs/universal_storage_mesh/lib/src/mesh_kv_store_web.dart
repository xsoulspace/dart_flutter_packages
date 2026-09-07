/// Web (`localStorage`) persistence for mesh replicas.
///
/// Selected by the conditional import in `mesh_storage_provider.dart` /
/// `mesh_peer_registry.dart` when `dart:js_interop` is available. The
/// requested replica root (`MeshStorageConfig.storePath`) is **not** a
/// filesystem path here — it is only used as the `localStorage` namespace,
/// so two replicas configured with different roots stay isolated; two
/// browser tabs sharing the same root share the same persisted state.
///
/// Records survive page reloads while `localStorage` works. When it is
/// unavailable or throws (quota, privacy mode, embedded webviews), the
/// store degrades gracefully to in-memory persistence for the page
/// session; a reload then starts a fresh replica and pairs again.
library;

import 'package:web/web.dart' as web;

import 'mesh_kv_store.dart';

/// `localStorage`-backed store with an in-memory fallback.
final class WebMeshKvStore implements MeshKeyValueStore {
  /// Creates a store namespaced under [root]. The root is embedded
  /// verbatim in the `localStorage` key prefix; it is never touched as a
  /// filesystem path.
  WebMeshKvStore({required this.root})
    : _prefix = 'universal_storage_mesh:$root:';

  /// Replica root; used only as the persistence namespace on web.
  final String root;

  final String _prefix;
  final MemoryMeshKvStore _fallback = MemoryMeshKvStore();

  /// `null` when `localStorage` is unusable; every access is also
  /// guarded so quota/privacy failures degrade to [_fallback].
  web.Storage? get _storage {
    try {
      return web.window.localStorage;
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<String?> read(final String key) async {
    final storage = _storage;
    if (storage != null) {
      try {
        final value = storage.getItem('$_prefix$key');
        if (value != null) return value;
      } on Object catch (_) {
        // Fall through to the in-memory fallback.
      }
    }
    return _fallback.read(key);
  }

  @override
  Future<void> write(final String key, final String value) async {
    final storage = _storage;
    if (storage != null) {
      try {
        storage.setItem('$_prefix$key', value);
        return;
      } on Object catch (_) {
        // Quota exceeded / storage blocked: keep the session running.
      }
    }
    await _fallback.write(key, value);
  }

  @override
  Future<List<String>> list(final String prefix) async {
    final keys = <String>{};
    final storage = _storage;
    if (storage != null) {
      try {
        for (var i = 0; i < storage.length; i++) {
          final storageKey = storage.key(i);
          if (storageKey == null) continue;
          if (!storageKey.startsWith('$_prefix$prefix')) continue;
          keys.add(storageKey.substring(_prefix.length));
        }
      } on Object catch (_) {
        // Unreadable storage: rely on the fallback below.
      }
    }
    // In-memory fallback entries mirror anything persisted this session
    // that `localStorage` refused; they shadow persisted values.
    keys.addAll(await _fallback.list(prefix));
    return (keys.toList()..sort());
  }
}

/// Web-backed selection for the conditional import in
/// `mesh_storage_provider.dart` / `mesh_peer_registry.dart`.
MeshKeyValueStore createMeshKvStore(final String root) =>
    WebMeshKvStore(root: root);
