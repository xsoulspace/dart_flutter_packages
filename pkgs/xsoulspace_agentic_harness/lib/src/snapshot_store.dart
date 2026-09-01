import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

import 'snapshot.dart';

/// Durable session store over the agent-harness world snapshot codec.
///
/// Thin persistence layer: every [save] encodes the full world via
/// [snapshotWorld], every [load] restores a fresh one via [restoreWorld].
/// No caching, no migration logic beyond an envelope version check.
///
/// ```dart
/// final store = SnapshotStore();
/// await store.open(appSupportDirPath);
/// await store.save(world, name: 'current', meta: {'scene': 'act-1'});
/// final restored = await store.load('current');
/// ```
class SnapshotStore {
  /// Creates a store. When [storage] is injected it is used as-is (tests,
  /// alternate backends); otherwise call [open] once to build a lazily
  /// initialized [FileSystemStorageProvider] rooted at a base directory.
  SnapshotStore({StorageService? storage, this.directory = 'harness-sessions'})
    : _external = storage;

  static const String _schemaTag = 'agent-harness-snapshot';
  static const int _envelopeVersion = 1;

  /// Mirrors the codec's snapshot version at capture time.
  static const int _worldSnapshotVersion = 1;
  static const String _extension = '.json';

  /// Directory, relative to the storage root, holding session files.
  final String directory;

  final StorageService? _external;
  StorageService? _default;

  /// Initializes the default filesystem storage rooted at [basePath].
  ///
  /// No-op when a [StorageService] was injected at construction.
  Future<void> open(String basePath) async {
    if (_external != null) return;
    final service = StorageService(FileSystemStorageProvider());
    await service.initializeWithConfig(
      FileSystemConfig.fromFilePathConfig(
        FilePathConfig.create(
          path: basePath,
          macOSBookmarkData: MacOSBookmark.empty,
        ),
      ),
    );
    _default = service;
  }

  StorageService get _service {
    final service = _external ?? _default;
    if (service == null) {
      throw StateError(
        'SnapshotStore.open() must be awaited before use '
        'when no StorageService was injected.',
      );
    }
    return service;
  }

  /// Storage-relative path of session file [name].
  String sessionPath(String name) => '$directory/$name$_extension';

  /// Encodes [world] and writes it to [sessionPath] for [name].
  ///
  /// [meta] rides in the envelope alongside the world payload. Returns the
  /// written path.
  Future<String> save(
    World world, {
    String name = 'current',
    Map<String, Object?> meta = const <String, Object?>{},
  }) async {
    final envelope = <String, Object?>{
      'schema': _schemaTag,
      'version': _envelopeVersion,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'meta': meta,
      'world': snapshotWorld(world),
    };
    final path = sessionPath(name);
    await _service.saveFile(path, jsonEncode(envelope));
    return path;
  }

  /// Reads session [name], validates its envelope, and restores a fresh
  /// [World]. Throws [SnapshotNotFoundException] when no such session exists
  /// and [SnapshotFormatException] when the payload is unreadable.
  Future<World> load(String name) async {
    final path = sessionPath(name);
    final raw = await _service.readFile(path);
    if (raw == null) {
      throw SnapshotNotFoundException('No session "$name" at $path.');
    }
    if (raw.isEmpty) {
      throw SnapshotFormatException('Session "$name" at $path is empty.');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw SnapshotFormatException(
        'Session "$name" at $path is not valid JSON.',
        error,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw SnapshotFormatException(
        'Session "$name" at $path is not an object envelope.',
      );
    }
    if (decoded['schema'] != _schemaTag) {
      throw SnapshotFormatException(
        'Session "$name" has unknown schema "${decoded['schema']}".',
      );
    }
    if (decoded['version'] != _envelopeVersion) {
      throw SnapshotFormatException(
        'Session "$name" has unsupported version "${decoded['version']}".',
      );
    }
    final world = decoded['world'];
    if (world is! Map<String, dynamic>) {
      throw SnapshotFormatException(
        'Session "$name" carries no world payload.',
      );
    }
    if (world['format'] != kSnapshotFormat ||
        world['version'] != _worldSnapshotVersion) {
      throw SnapshotFormatException(
        'Session "$name" world payload is corrupt or from an unsupported '
        'codec format.',
      );
    }
    return restoreWorld(world);
  }

  /// Reads session [name]'s raw envelope (meta + world payload) WITHOUT
  /// restoring. P5: hosts need the metadata (task id, jail path) BEFORE
  /// deciding whether/how to restore.
  Future<Map<String, dynamic>> loadEnvelope(String name) async {
    final path = sessionPath(name);
    final raw = await _service.readFile(path);
    if (raw == null) {
      throw SnapshotNotFoundException('No session "$name" at $path.');
    }
    if (raw.isEmpty) {
      throw SnapshotFormatException('Session "$name" at $path is empty.');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw SnapshotFormatException(
        'Session "$name" at $path is not valid JSON.',
        error,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw SnapshotFormatException(
        'Session "$name" is not an object envelope.',
      );
    }
    if (decoded['schema'] != _schemaTag) {
      throw SnapshotFormatException(
        'Session "$name" has unknown schema "${decoded['schema']}".',
      );
    }
    if (decoded['version'] != _envelopeVersion) {
      throw SnapshotFormatException(
        'Session "$name" has unsupported version "${decoded['version']}".',
      );
    }
    return decoded;
  }

  /// Lists saved session names, sorted, without extension.
  Future<List<String>> listSessions() async {
    final entries = await _service.listDirectory(directory);
    return [
      for (final entry in entries)
        if (!entry.isDirectory && entry.name.endsWith(_extension))
          entry.name.substring(0, entry.name.length - _extension.length),
    ]..sort();
  }

  /// Deletes session [name].
  Future<void> delete(String name) async {
    await _service.removeFile(sessionPath(name));
  }
}

/// Base failure type for [SnapshotStore] operations.
class SnapshotStoreException implements Exception {
  const SnapshotStoreException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'SnapshotStoreException: $message'
      : 'SnapshotStoreException: $message\nCaused by: $cause';
}

/// No session file exists under the requested name.
class SnapshotNotFoundException extends SnapshotStoreException {
  const SnapshotNotFoundException(super.message);
}

/// Session file exists but its envelope or world payload is unreadable.
class SnapshotFormatException extends SnapshotStoreException {
  const SnapshotFormatException(super.message, [super.cause]);
}
