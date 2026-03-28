import 'dart:async';

import 'package:from_json_to_json/from_json_to_json.dart';
import 'package:is_dart_empty_or_not/is_dart_empty_or_not.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart' show LocalDbI;

/// Local engine adapter backed by [LocalDbI].
class LocalDbStorageProvider extends StorageProvider implements LocalEngine {
  /// Creates local-db storage provider.
  LocalDbStorageProvider({required this.localDb});

  /// Backing key-value storage.
  final LocalDbI localDb;

  StorageConfig? _config;
  var _initialized = false;
  Future<void> _mutationQueue = Future<void>.value();

  String get _bucketStorageKey {
    final prefix = _resolveKeyspacePrefix(_config).whenEmptyUse(
      'universal_storage',
    );
    return 'us_local_db/$prefix/files';
  }

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! FileSystemConfig && config is! LocalDbStorageConfig) {
      throw ArgumentError(
        'Expected FileSystemConfig or LocalDbStorageConfig, got '
        '${config.runtimeType}',
      );
    }

    _config = config;
    await localDb.init();
    _initialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => _initialized;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) => _enqueueMutation<FileOperationResult>(() async {
    _ensureInitialized();
    final normalizedPath = _normalizePath(path);
    final bucket = await _readBucket();
    if (bucket.containsKey(normalizedPath)) {
      throw FileAlreadyExistsException(
        'File already exists at path: $normalizedPath',
      );
    }

    bucket[normalizedPath] = _recordFromContent(content);
    await _writeBucket(bucket);
    return FileOperationResult.created(path: normalizedPath);
  });

  @override
  Future<String?> getFile(final String path) async {
    _ensureInitialized();
    final normalizedPath = _normalizePath(path);
    final bucket = await _readBucket();
    final rawRecord = bucket[normalizedPath];
    if (rawRecord == null) {
      return null;
    }
    final record = _decodeRecord(rawRecord);
    return jsonDecodeString(record['content']);
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) => _enqueueMutation<FileOperationResult>(() async {
    _ensureInitialized();
    final normalizedPath = _normalizePath(path);
    final bucket = await _readBucket();
    if (!bucket.containsKey(normalizedPath)) {
      throw FileNotFoundException('File not found at path: $normalizedPath');
    }

    bucket[normalizedPath] = _recordFromContent(content);
    await _writeBucket(bucket);
    return FileOperationResult.updated(path: normalizedPath);
  });

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) => _enqueueMutation<FileOperationResult>(() async {
    _ensureInitialized();
    final normalizedPath = _normalizePath(path);
    final bucket = await _readBucket();
    if (!bucket.containsKey(normalizedPath)) {
      throw FileNotFoundException('File not found at path: $normalizedPath');
    }

    bucket.remove(normalizedPath);
    await _writeBucket(bucket);
    return FileOperationResult.deleted(path: normalizedPath);
  });

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();
    final normalizedDirectory = _normalizeDirectoryPath(directoryPath);
    final bucket = await _readBucket();
    final directories = <String, FileEntry>{};
    final files = <String, FileEntry>{};

    for (final bucketEntry in bucket.entries) {
      final fullPath = jsonDecodeString(bucketEntry.key);
      if (fullPath.isEmpty) {
        continue;
      }
      if (normalizedDirectory.isNotEmpty &&
          !fullPath.startsWith('$normalizedDirectory/')) {
        continue;
      }

      final relativePath = normalizedDirectory.isEmpty
          ? fullPath
          : fullPath.substring(normalizedDirectory.length + 1);
      if (relativePath.isEmpty) {
        continue;
      }

      final segments = relativePath.split('/');
      if (segments.length == 1) {
        final record = _decodeRecord(bucketEntry.value);
        final content = jsonDecodeString(record['content']);
        files[segments.single] = FileEntry(
          name: segments.single,
          isDirectory: false,
          size: content.length,
          modifiedAt: _decodeModifiedAt(record),
        );
        continue;
      }

      final directoryName = segments.first;
      directories.putIfAbsent(
        directoryName,
        () => FileEntry(
          name: directoryName,
          isDirectory: true,
          modifiedAt: DateTime.now().toUtc(),
        ),
      );
    }

    final entries = <FileEntry>[...directories.values, ...files.values]
      ..sort((final a, final b) => a.name.compareTo(b.name));
    return entries;
  }

  @override
  Future<void> restore(final String path, {final String? versionId}) {
    throw const UnsupportedOperationException(
      'LocalDbStorageProvider does not support restore/versioning.',
    );
  }

  @override
  bool get supportsSync => false;

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {}

  @override
  Future<void> dispose() async {
    await _mutationQueue;
    _initialized = false;
  }

  Future<T> _enqueueMutation<T>(final Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationQueue = _mutationQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> _readBucket() async {
    final rawBucket = await localDb.getMap(_bucketStorageKey);
    final bucket = jsonDecodeMap(rawBucket).whenEmptyUse(
      const <String, dynamic>{},
    );
    return Map<String, dynamic>.from(bucket);
  }

  Future<void> _writeBucket(final Map<String, dynamic> bucket) async {
    await localDb.setMap(key: _bucketStorageKey, value: bucket);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const ConfigurationException(
        'Provider not initialized. Call initWithConfig() first.',
      );
    }
  }

  String _resolveKeyspacePrefix(final StorageConfig? config) {
    if (config is LocalDbStorageConfig) {
      final normalizedPrefix = _normalizeConfigPath(config.keyspacePrefix);
      return normalizedPrefix.whenEmptyUse('universal_storage');
    }
    if (config is FileSystemConfig) {
      final normalizedPath = _normalizeConfigPath(config.basePath);
      final databaseName = config.databaseName.trim();
      return databaseName.whenEmptyUse(normalizedPath);
    }
    return 'universal_storage';
  }

  Map<String, dynamic> _recordFromContent(final String content) =>
      <String, dynamic>{
        'content': content,
        'updated_at_utc': DateTime.now().toUtc().toIso8601String(),
      };

  Map<String, dynamic> _decodeRecord(final Object? rawRecord) =>
      jsonDecodeMap(rawRecord).whenEmptyUse(const <String, dynamic>{});

  DateTime _decodeModifiedAt(final Map<String, dynamic> record) {
    final rawTimestamp = jsonDecodeString(record['updated_at_utc']);
    final timestamp = DateTime.tryParse(rawTimestamp)?.toUtc();
    return timestamp ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  String _normalizePath(final String path) {
    final normalized = path
        .trim()
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('/+'), '/')
        .replaceFirst(RegExp('^/'), '')
        .replaceFirst(RegExp(r'/$'), '');
    if (normalized.isEmpty) {
      throw const ConfigurationException('Path cannot be empty.');
    }
    return normalized;
  }

  String _normalizeDirectoryPath(final String directoryPath) {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      return '';
    }
    return _normalizePath(trimmed);
  }

  String _normalizeConfigPath(final String path) => path
      .trim()
      .replaceAll(r'\', '/')
      .replaceAll(RegExp('/+'), '/')
      .replaceFirst(RegExp('^/'), '')
      .replaceFirst(RegExp(r'/$'), '');
}
