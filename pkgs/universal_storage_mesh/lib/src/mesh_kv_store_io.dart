/// `dart:io` file-backed persistence for mesh replicas.
///
/// Reproduces the original on-disk layout byte-for-byte: keys map to
/// `<root>/<key>` paths (`peers.json`, `docs/<shard>.json`), and the
/// `docs/` directory is created eagerly at construction as before.
library;

import 'dart:io';

import 'mesh_kv_store.dart';

/// Key-value store persisted as files under [root].
final class FileMeshKvStore implements MeshKeyValueStore {
  FileMeshKvStore(this.root) {
    Directory('$root/docs').createSync(recursive: true);
  }

  /// Absolute or relative directory this replica persists under.
  final String root;

  String _pathOf(final String key) => '$root/$key';

  @override
  Future<String?> read(final String key) async {
    final file = File(_pathOf(key));
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(final String key, final String value) async {
    final file = File(_pathOf(key));
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }

  @override
  Future<List<String>> list(final String prefix) async {
    final directory = Directory('$root/$prefix');
    if (!directory.existsSync()) return const [];
    final keys = <String>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      keys.add('$prefix/${entity.uri.pathSegments.last}');
    }
    return (keys..sort());
  }
}

/// File-backed selection for the conditional import in
/// `mesh_storage_provider.dart` / `mesh_peer_registry.dart`.
MeshKeyValueStore createMeshKvStore(final String root) => FileMeshKvStore(root);
