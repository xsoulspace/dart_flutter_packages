import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'mesh_kv_store.dart';
import 'mesh_kv_store_factory.dart'
    if (dart.library.js_interop) 'mesh_kv_store_web.dart'
    if (dart.library.io) 'mesh_kv_store_io.dart';

/// Durable registry of paired peers (the outcome of QR scanning,
/// ADR 0010 §3). v1 stores records as JSON; key material handling arrives
/// with real transports.
///
/// Persistence goes through [MeshKeyValueStore], so the registry works on
/// every platform: file-backed where `dart:io` exists (original behavior,
/// unchanged) and `localStorage`-backed on web. On web, [filePath] is
/// only used to derive the persistence namespace — it is never used as a
/// filesystem path.
final class MeshPeerRegistry {
  /// Registry persisted at the posix [filePath] of the registry file
  /// (e.g. `<storePath>/peers.json`). On web the path only feeds the
  /// persistence namespace; records survive reloads via `localStorage`.
  factory MeshPeerRegistry({required final String filePath}) {
    final slash = filePath.lastIndexOf('/');
    final key = slash < 0 ? filePath : filePath.substring(slash + 1);
    final root = slash <= 0 ? '.' : filePath.substring(0, slash);
    return MeshPeerRegistry._(createMeshKvStore(root), key, filePath);
  }

  MeshPeerRegistry._(this._store, this._key, this.filePath);

  /// In-memory registry for browser-only examples and tests.
  MeshPeerRegistry.inMemory() : _store = null, _key = '', filePath = '';

  final MeshKeyValueStore? _store;
  final String _key;

  /// Posix path the registry was opened from ('' for in-memory and
  /// store-backed registries). Diagnostic only; never touched as a
  /// filesystem path on web.
  final String filePath;

  final Map<String, MeshPeerRecord> _peers = {};

  static Future<MeshPeerRegistry> load(final String filePath) {
    final slash = filePath.lastIndexOf('/');
    final key = slash < 0 ? filePath : filePath.substring(slash + 1);
    final root = slash <= 0 ? '.' : filePath.substring(0, slash);
    return loadFromStore(
      store: createMeshKvStore(root),
      key: key,
      filePath: filePath,
    );
  }

  /// Loads a registry backed by an existing replica store, sharing its
  /// persistence medium. Used by [MeshStorageProvider] so registry and
  /// doc shards always land on the same backing.
  static Future<MeshPeerRegistry> loadFromStore({
    required final MeshKeyValueStore store,
    required final String key,
    final String filePath = '',
  }) async {
    final registry = MeshPeerRegistry._(store, key, filePath);
    final raw = await store.read(key);
    if (raw == null) return registry;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final entry in decoded.whereType<Map<dynamic, dynamic>>()) {
          final peer = MeshPeerRecord.fromJson(
            Map<String, dynamic>.from(entry),
          );
          registry._peers[peer.peerId] = peer;
        }
      }
    } on FormatException {
      // Corrupt registry starts empty; pairing re-adds peers.
    }
    return registry;
  }

  Iterable<MeshPeerRecord> get peers => _peers.values;

  MeshPeerRecord? byId(final String peerId) => _peers[peerId];

  Future<void> register(final MeshPeerRecord peer) async {
    _peers[peer.peerId] = peer;
    await persist();
  }

  @visibleForTesting
  Future<void> persist() async {
    final store = _store;
    if (store == null) return;
    await store.write(
      _key,
      jsonEncode(_peers.values.map((final p) => p.toJson()).toList()),
    );
  }
}
