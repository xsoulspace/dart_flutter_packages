import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';
import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

import 'cloudkit_payload_too_large_exception.dart';

/// CloudKit-backed storage provider for Universal Storage.
class CloudKitStorageProvider extends StorageProvider implements RemoteEngine {
  CloudKitStorageProvider({
    final CloudKitBridge? bridge,
    final _LocalMirrorStore Function()? localMirrorFactory,
    final StorageProvider Function(StorageConfig config)? fallbackResolver,
  }) : _bridge = bridge ?? CloudKitBridgePlatform.instance,
       _localMirrorFactory = localMirrorFactory ?? _defaultLocalMirrorFactory,
       _fallbackResolver = fallbackResolver;

  static const _stateSchemaVersion = 1;
  static const _stateRelativePath = '.us/cloudkit/state_v1.json';

  final CloudKitBridge _bridge;
  final _LocalMirrorStore Function() _localMirrorFactory;
  final StorageProvider Function(StorageConfig config)? _fallbackResolver;

  CloudKitConfig? _config;
  _LocalMirrorStore? _localMirror;
  StorageProvider? _fallback;
  _MirrorState _mirrorState = const _MirrorState();
  var _initialized = false;
  var _delegatingToFallback = false;

  @override
  StorageCapabilities get declaredCapabilities => const StorageCapabilities(
    supportsRevisionMetadata: true,
    supportsManualConflictResolution: true,
    supportsBackgroundSync: true,
  );

  @override
  Future<StorageCapabilities> resolveCapabilities() async =>
      declaredCapabilities;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! CloudKitConfig) {
      throw ArgumentError('Expected CloudKitConfig, got ${config.runtimeType}');
    }

    _config = config;
    _fallback = null;
    _localMirror = null;
    _mirrorState = const _MirrorState();
    _initialized = false;
    _delegatingToFallback = false;

    try {
      await _bridge.initialize(CloudKitBridgeConfig.fromStorageConfig(config));
      if (config.dataMode == CloudKitDataMode.localMirror) {
        await _initializeLocalMirror(config);
      }
      _initialized = true;
    } on CloudKitBridgeException catch (error) {
      await _activateFallbackOrThrow(
        reason: error.message,
        isUnsupported: error.code == CloudKitBridgeErrorCode.unsupported,
      );
    } on StorageException catch (error) {
      await _activateFallbackOrThrow(reason: error.message);
    } catch (error) {
      await _activateFallbackOrThrow(reason: error.toString());
    }
  }

  @override
  Future<bool> isAuthenticated() async {
    if (_delegatingToFallback) {
      return _fallback?.isAuthenticated() ?? false;
    }
    return _initialized;
  }

  @override
  bool get supportsSync {
    if (_delegatingToFallback) {
      return _fallback?.supportsSync ?? false;
    }
    return true;
  }

  @override
  Future<FileOperationResult> createFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    if (_delegatingToFallback) {
      return _fallback!.createFile(
        filePath,
        content,
        commitMessage: commitMessage,
      );
    }
    _ensureInitialized();

    if (_config!.dataMode == CloudKitDataMode.localMirror) {
      return _createLocal(filePath, content, commitMessage: commitMessage);
    }

    return _createRemote(filePath, content);
  }

  @override
  Future<String?> getFile(final String filePath) async {
    if (_delegatingToFallback) {
      return _fallback!.getFile(filePath);
    }
    _ensureInitialized();

    if (_config!.dataMode == CloudKitDataMode.localMirror) {
      return _localMirror!.getFile(filePath);
    }

    final normalizedPath = _normalizePath(filePath);
    final record = await _fetchRemoteRecordByPath(normalizedPath);
    return record?.content;
  }

  @override
  Future<FileOperationResult> updateFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    if (_delegatingToFallback) {
      return _fallback!.updateFile(
        filePath,
        content,
        commitMessage: commitMessage,
      );
    }
    _ensureInitialized();

    if (_config!.dataMode == CloudKitDataMode.localMirror) {
      return _updateLocal(filePath, content, commitMessage: commitMessage);
    }

    return _updateRemote(filePath, content);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String filePath, {
    final String? commitMessage,
  }) async {
    if (_delegatingToFallback) {
      return _fallback!.deleteFile(filePath, commitMessage: commitMessage);
    }
    _ensureInitialized();

    if (_config!.dataMode == CloudKitDataMode.localMirror) {
      return _deleteLocal(filePath, commitMessage: commitMessage);
    }

    return _deleteRemote(filePath);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    if (_delegatingToFallback) {
      return _fallback!.listDirectory(directoryPath);
    }
    _ensureInitialized();

    if (_config!.dataMode == CloudKitDataMode.localMirror) {
      return _localMirror!.listDirectory(directoryPath);
    }

    final normalizedPrefix = _normalizePrefix(directoryPath);
    final records = await _queryRemotePrefix(normalizedPrefix);
    return _immediateChildrenFromRecords(
      normalizedPrefix: normalizedPrefix,
      records: records,
    );
  }

  @override
  Future<void> restore(final String filePath, {final String? versionId}) async {
    if (_delegatingToFallback) {
      await _fallback!.restore(filePath, versionId: versionId);
      return;
    }

    throw const UnsupportedOperationException(
      'CloudKit provider does not support restore() in v1.',
    );
  }

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {
    if (_delegatingToFallback) {
      if (!(_fallback?.supportsSync ?? false)) {
        throw CapabilityMismatchException(
          'Fallback provider (${_fallback.runtimeType}) does not support sync.',
        );
      }
      await _fallback!.sync(
        pullMergeStrategy: pullMergeStrategy,
        pushConflictStrategy: pushConflictStrategy,
      );
      return;
    }

    _ensureInitialized();

    if (_config!.dataMode == CloudKitDataMode.remoteOnly) {
      final delta = await _fetchRemoteChanges(
        serverChangeToken: _mirrorState.serverChangeToken,
      );
      _mirrorState = _mirrorState.copyWith(
        serverChangeToken: delta.nextServerChangeToken,
      );
      return;
    }

    final pullStrategy = _parseStrategy(pullMergeStrategy);
    final pushStrategy = _parseStrategy(pushConflictStrategy);

    final delta = await _fetchRemoteChanges(
      serverChangeToken: _mirrorState.serverChangeToken,
    );

    final pullConflicts = <String>[];
    for (final deletedPath in delta.deletedPaths) {
      final conflict = await _applyRemoteDeletion(deletedPath, pullStrategy);
      if (conflict != null) {
        pullConflicts.add(conflict);
      }
    }

    for (final record in delta.updatedRecords) {
      final conflict = await _applyRemoteUpdate(record, pullStrategy);
      if (conflict != null) {
        pullConflicts.add(conflict);
      }
    }

    if (pullConflicts.isNotEmpty) {
      throw SyncConflictException(
        'CloudKit pull conflicts require resolution: '
        '${pullConflicts.join(', ')}',
      );
    }

    final pushConflicts = await _pushLocalDiff(pushStrategy);
    if (pushConflicts.isNotEmpty) {
      throw SyncConflictException(
        'CloudKit push conflicts require resolution: '
        '${pushConflicts.join(', ')}',
      );
    }

    final manifest = await _buildManifestFromLocalMirror();
    _mirrorState = _mirrorState.copyWith(
      serverChangeToken: delta.nextServerChangeToken,
      manifest: manifest,
    );
    await _persistMirrorState();
  }

  @override
  Future<void> dispose() async {
    await _fallback?.dispose();
    await _localMirror?.dispose();
    await _bridge.dispose();
    _fallback = null;
    _localMirror = null;
    _mirrorState = const _MirrorState();
    _initialized = false;
    _delegatingToFallback = false;
  }

  Future<void> _initializeLocalMirror(final CloudKitConfig config) async {
    final localConfig = config.localMirrorConfig;
    if (localConfig == null || localConfig.isEmpty) {
      throw const ConfigurationException(
        'CloudKit localMirror mode requires a non-empty localMirrorConfig.',
      );
    }

    final localMirror = _localMirrorFactory();
    await localMirror.init(localConfig);
    _localMirror = localMirror;
    _mirrorState = await _loadMirrorState();
  }

  Future<void> _activateFallbackOrThrow({
    required final String reason,
    final bool isUnsupported = false,
  }) async {
    final config = _config;
    if (config == null) {
      throw UnsupportedOperationException(
        'CloudKit initialization failed before configuration was assigned: '
        '$reason',
      );
    }

    final fallbackConfig = config.fallbackConfig;
    if (fallbackConfig == null) {
      final platformReason = isUnsupported
          ? 'unsupported platform ${_platformLabel()}'
          : 'bridge initialization failure on ${_platformLabel()}';
      throw UnsupportedOperationException(
        'CloudKit unavailable ($platformReason): $reason',
      );
    }

    final fallbackProvider =
        _fallbackResolver?.call(fallbackConfig) ??
        StorageProviderRegistry.resolve(fallbackConfig);
    await fallbackProvider.initWithConfig(fallbackConfig);
    _fallback = fallbackProvider;
    _delegatingToFallback = true;
    _initialized = true;
  }

  FileOperationResult _resultFromRecord(
    final CloudKitRecord record, {
    required final bool created,
  }) {
    final metadata = <String, dynamic>{
      'provider': 'cloudkit',
      'recordName': record.recordName,
      'checksum': record.checksum,
      'size': record.size,
      'updatedAt': record.updatedAt.toUtc().toIso8601String(),
    };

    return created
        ? FileOperationResult.created(
            path: record.path,
            revisionId: record.recordName,
            metadata: metadata,
          )
        : FileOperationResult.updated(
            path: record.path,
            revisionId: record.recordName,
            metadata: metadata,
          );
  }

  Future<FileOperationResult> _createRemote(
    final String filePath,
    final String content,
  ) async {
    final normalizedPath = _normalizePath(filePath);
    final existing = await _fetchRemoteRecordByPath(normalizedPath);
    if (existing != null) {
      throw FileAlreadyExistsException(
        'File already exists at path: $normalizedPath',
      );
    }

    final record = _buildRecord(normalizedPath, content);
    await _saveRemoteRecord(record);
    return _resultFromRecord(record, created: true);
  }

  Future<FileOperationResult> _updateRemote(
    final String filePath,
    final String content,
  ) async {
    final normalizedPath = _normalizePath(filePath);
    final existing = await _fetchRemoteRecordByPath(normalizedPath);
    if (existing == null) {
      throw FileNotFoundException('File not found at path: $normalizedPath');
    }

    final record = _buildRecord(
      normalizedPath,
      content,
      changeTag: existing.changeTag,
    );
    await _saveRemoteRecord(record);
    return _resultFromRecord(record, created: false);
  }

  Future<FileOperationResult> _deleteRemote(final String filePath) async {
    final normalizedPath = _normalizePath(filePath);
    final existing = await _fetchRemoteRecordByPath(normalizedPath);
    if (existing == null) {
      throw FileNotFoundException('File not found at path: $normalizedPath');
    }

    try {
      await _bridge.deleteRecord(existing.recordName);
    } on CloudKitBridgeException catch (error) {
      throw _mapBridgeException(
        error,
        defaultMessage: 'Failed to delete remote record for $normalizedPath',
      );
    }

    return FileOperationResult.deleted(
      path: normalizedPath,
      revisionId: existing.recordName,
      metadata: <String, dynamic>{
        'provider': 'cloudkit',
        'recordName': existing.recordName,
      },
    );
  }

  Future<FileOperationResult> _createLocal(
    final String filePath,
    final String content, {
    required final String? commitMessage,
  }) async {
    final result = await _localMirror!.createFile(
      filePath,
      content,
      commitMessage: commitMessage,
    );

    _mirrorState = _mirrorState.withManifestEntry(
      _normalizePath(filePath),
      _ManifestEntry(
        checksum: normalizedSha256Hex(content),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await _persistMirrorState();
    return result;
  }

  Future<FileOperationResult> _updateLocal(
    final String filePath,
    final String content, {
    required final String? commitMessage,
  }) async {
    final result = await _localMirror!.updateFile(
      filePath,
      content,
      commitMessage: commitMessage,
    );

    _mirrorState = _mirrorState.withManifestEntry(
      _normalizePath(filePath),
      _ManifestEntry(
        checksum: normalizedSha256Hex(content),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await _persistMirrorState();
    return result;
  }

  Future<FileOperationResult> _deleteLocal(
    final String filePath, {
    required final String? commitMessage,
  }) async {
    final normalizedPath = _normalizePath(filePath);
    final result = await _localMirror!.deleteFile(
      normalizedPath,
      commitMessage: commitMessage,
    );
    _mirrorState = _mirrorState.withoutManifestEntry(normalizedPath);
    await _persistMirrorState();
    return result;
  }

  Future<CloudKitRecord?> _fetchRemoteRecordByPath(final String path) async {
    try {
      return await _bridge.fetchRecordByPath(path);
    } on CloudKitBridgeException catch (error) {
      throw _mapBridgeException(
        error,
        defaultMessage: 'Failed to fetch remote record for $path',
      );
    }
  }

  Future<void> _saveRemoteRecord(final CloudKitRecord record) async {
    try {
      await _bridge.saveRecord(record);
    } on CloudKitBridgeException catch (error) {
      throw _mapBridgeException(
        error,
        defaultMessage: 'Failed to save remote record for ${record.path}',
      );
    }
  }

  Future<List<CloudKitRecord>> _queryRemotePrefix(final String prefix) async {
    try {
      return await _bridge.queryByPathPrefix(prefix);
    } on CloudKitBridgeException catch (error) {
      throw _mapBridgeException(
        error,
        defaultMessage: 'Failed to query CloudKit prefix "$prefix"',
      );
    }
  }

  Future<CloudKitDelta> _fetchRemoteChanges({
    required final String? serverChangeToken,
  }) async {
    try {
      return await _bridge.fetchChanges(serverChangeToken: serverChangeToken);
    } on CloudKitBridgeException catch (error) {
      throw _mapBridgeException(
        error,
        defaultMessage: 'Failed to fetch CloudKit delta',
      );
    }
  }

  StorageException _mapBridgeException(
    final CloudKitBridgeException error, {
    required final String defaultMessage,
  }) {
    final message = error.message.trim().isEmpty
        ? defaultMessage
        : error.message;

    return switch (error.code) {
      CloudKitBridgeErrorCode.authentication => AuthenticationException(
        message,
      ),
      CloudKitBridgeErrorCode.network ||
      CloudKitBridgeErrorCode.transient => NetworkException(message),
      CloudKitBridgeErrorCode.conflict => SyncConflictException(message),
      CloudKitBridgeErrorCode.notFound => FileNotFoundException(message),
      CloudKitBridgeErrorCode.payloadTooLarge => ConfigurationException(
        message,
      ),
      CloudKitBridgeErrorCode.unsupported => UnsupportedOperationException(
        message,
      ),
      CloudKitBridgeErrorCode.unknown => NetworkException(message),
    };
  }

  CloudKitRecord _buildRecord(
    final String normalizedPath,
    final String content, {
    final String? changeTag,
  }) {
    final payloadBytes = utf8.encode(content).length;
    if (payloadBytes > _config!.maxInlineBytes) {
      final error = CloudKitPayloadTooLargeException(
        path: normalizedPath,
        payloadBytes: payloadBytes,
        maxInlineBytes: _config!.maxInlineBytes,
      );
      throw ConfigurationException(error.message);
    }

    final updatedAt = DateTime.now().toUtc();
    return CloudKitRecord(
      recordName: sha256Hex(normalizedPath),
      path: normalizedPath,
      content: content,
      checksum: normalizedSha256Hex(content),
      size: payloadBytes,
      updatedAt: updatedAt,
      changeTag: changeTag,
    );
  }

  Future<String?> _applyRemoteUpdate(
    final CloudKitRecord record,
    final ConflictResolutionStrategy strategy,
  ) async {
    final localContent = await _localMirror!.getFile(record.path);
    if (localContent == null) {
      await _localMirror!.createFile(record.path, record.content);
      _mirrorState = _mirrorState.withManifestEntry(
        record.path,
        _ManifestEntry(checksum: record.checksum, updatedAt: record.updatedAt),
      );
      return null;
    }

    final localChecksum = normalizedSha256Hex(localContent);
    if (localChecksum == record.checksum) {
      _mirrorState = _mirrorState.withManifestEntry(
        record.path,
        _ManifestEntry(checksum: record.checksum, updatedAt: record.updatedAt),
      );
      return null;
    }

    switch (strategy) {
      case ConflictResolutionStrategy.serverAlwaysRight:
        await _localMirror!.updateFile(record.path, record.content);
        _mirrorState = _mirrorState.withManifestEntry(
          record.path,
          _ManifestEntry(
            checksum: record.checksum,
            updatedAt: record.updatedAt,
          ),
        );
        return null;
      case ConflictResolutionStrategy.clientAlwaysRight:
        // Keep local source-of-truth and force push in _pushLocalDiff by
        // storing remote checksum as last-known remote state.
        _mirrorState = _mirrorState.withManifestEntry(
          record.path,
          _ManifestEntry(
            checksum: record.checksum,
            updatedAt: record.updatedAt,
          ),
        );
        return null;
      case ConflictResolutionStrategy.manualResolution:
        return record.path;
      case ConflictResolutionStrategy.lastWriteWins:
        final localUpdatedAt =
            _mirrorState.manifest[record.path]?.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc();
        if (record.updatedAt.isAfter(localUpdatedAt)) {
          await _localMirror!.updateFile(record.path, record.content);
          _mirrorState = _mirrorState.withManifestEntry(
            record.path,
            _ManifestEntry(
              checksum: record.checksum,
              updatedAt: record.updatedAt,
            ),
          );
        } else {
          // Local is newer: keep local and force push by preserving remote
          // checksum in manifest.
          _mirrorState = _mirrorState.withManifestEntry(
            record.path,
            _ManifestEntry(
              checksum: record.checksum,
              updatedAt: record.updatedAt,
            ),
          );
        }
        return null;
    }
  }

  Future<String?> _applyRemoteDeletion(
    final String remotePath,
    final ConflictResolutionStrategy strategy,
  ) async {
    final localContent = await _localMirror!.getFile(remotePath);
    if (localContent == null) {
      _mirrorState = _mirrorState.withoutManifestEntry(remotePath);
      return null;
    }

    final localChecksum = normalizedSha256Hex(localContent);
    final manifestEntry = _mirrorState.manifest[remotePath];
    final localHasDrift =
        manifestEntry == null || manifestEntry.checksum != localChecksum;

    switch (strategy) {
      case ConflictResolutionStrategy.clientAlwaysRight:
        // Keep local source-of-truth and force recreation remotely on push.
        _mirrorState = _mirrorState.withoutManifestEntry(remotePath);
        return null;
      case ConflictResolutionStrategy.serverAlwaysRight:
        await _localMirror!.deleteFile(remotePath);
        _mirrorState = _mirrorState.withoutManifestEntry(remotePath);
        return null;
      case ConflictResolutionStrategy.manualResolution:
        if (localHasDrift) {
          return remotePath;
        }
        await _localMirror!.deleteFile(remotePath);
        _mirrorState = _mirrorState.withoutManifestEntry(remotePath);
        return null;
      case ConflictResolutionStrategy.lastWriteWins:
        if (localHasDrift) {
          // Local content diverged from last known remote snapshot.
          _mirrorState = _mirrorState.withoutManifestEntry(remotePath);
          return null;
        }
        await _localMirror!.deleteFile(remotePath);
        _mirrorState = _mirrorState.withoutManifestEntry(remotePath);
        return null;
    }
  }

  Future<List<String>> _pushLocalDiff(
    final ConflictResolutionStrategy strategy,
  ) async {
    final localFiles = await _readLocalMirrorFiles();
    final conflicts = <String>[];

    final deletedPaths = _mirrorState.manifest.keys
        .where((final key) => !localFiles.containsKey(key))
        .toList(growable: false);

    for (final entry in localFiles.entries) {
      final pathKey = entry.key;
      final localChecksum = normalizedSha256Hex(entry.value);
      final previous = _mirrorState.manifest[pathKey];
      if (previous != null && previous.checksum == localChecksum) {
        continue;
      }
      final localUpdatedAt = previous?.updatedAt ?? DateTime.now().toUtc();

      final remoteExisting = await _fetchRemoteRecordByPath(pathKey);
      final record = _buildRecord(
        pathKey,
        entry.value,
        changeTag: remoteExisting?.changeTag,
      );
      try {
        await _saveRemoteRecord(record);
      } on SyncConflictException {
        if (strategy == ConflictResolutionStrategy.manualResolution) {
          conflicts.add(pathKey);
        } else if (strategy == ConflictResolutionStrategy.serverAlwaysRight) {
          final remote = await _fetchRemoteRecordByPath(pathKey);
          if (remote != null) {
            await _applyRemoteUpdate(
              remote,
              ConflictResolutionStrategy.serverAlwaysRight,
            );
          }
        } else if (strategy == ConflictResolutionStrategy.lastWriteWins) {
          final remote = await _fetchRemoteRecordByPath(pathKey);
          if (remote == null || localUpdatedAt.isAfter(remote.updatedAt)) {
            await _saveRemoteRecord(record);
          } else {
            await _applyRemoteUpdate(
              remote,
              ConflictResolutionStrategy.serverAlwaysRight,
            );
          }
        } else {
          // Force overwrite for clientAlwaysRight.
          final forced = _buildRecord(pathKey, entry.value);
          await _saveRemoteRecord(forced);
        }
      }
    }

    for (final deletedPath in deletedPaths) {
      final remote = await _fetchRemoteRecordByPath(deletedPath);
      if (remote != null) {
        try {
          await _bridge.deleteRecord(remote.recordName);
        } on CloudKitBridgeException catch (error) {
          throw _mapBridgeException(
            error,
            defaultMessage: 'Failed to delete remote record for $deletedPath',
          );
        }
      }
    }

    return conflicts;
  }

  List<FileEntry> _immediateChildrenFromRecords({
    required final String normalizedPrefix,
    required final List<CloudKitRecord> records,
  }) {
    final entries = <String, FileEntry>{};
    final directoryPrefix = normalizedPrefix.isEmpty
        ? ''
        : '$normalizedPrefix/';

    for (final record in records) {
      final candidatePath = record.path;
      if (directoryPrefix.isNotEmpty &&
          candidatePath != normalizedPrefix &&
          !candidatePath.startsWith(directoryPrefix)) {
        continue;
      }

      final relative = normalizedPrefix.isEmpty
          ? candidatePath
          : candidatePath == normalizedPrefix
          ? path.basename(candidatePath)
          : candidatePath.substring(directoryPrefix.length);

      if (relative.isEmpty) {
        continue;
      }

      final segments = relative
          .split('/')
          .where((final e) => e.isNotEmpty)
          .toList();
      if (segments.isEmpty) {
        continue;
      }

      final first = segments.first;
      if (segments.length == 1) {
        entries[first] = FileEntry(
          name: first,
          isDirectory: false,
          size: record.size,
          modifiedAt: record.updatedAt,
        );
      } else {
        entries.putIfAbsent(
          first,
          () => FileEntry(
            name: first,
            isDirectory: true,
            modifiedAt: record.updatedAt,
          ),
        );
      }
    }

    final values = entries.values.toList()
      ..sort((final a, final b) => a.name.compareTo(b.name));
    return values;
  }

  Future<_MirrorState> _loadMirrorState() async {
    final stateFile = File(_mirrorStatePath());
    if (!stateFile.existsSync()) {
      return const _MirrorState();
    }

    try {
      final decoded = jsonDecode(await stateFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const _MirrorState();
      }

      final serverChangeToken = decoded['serverChangeToken']?.toString();
      final manifestJson = decoded['manifest'];
      final manifest = <String, _ManifestEntry>{};
      if (manifestJson is Map) {
        for (final entry in manifestJson.entries) {
          if (entry.value is! Map) {
            continue;
          }
          final map = Map<String, dynamic>.from(entry.value as Map);
          final checksum = (map['checksum'] ?? '').toString();
          final updatedAt =
              DateTime.tryParse((map['updatedAt'] ?? '').toString()) ??
              DateTime.fromMillisecondsSinceEpoch(0).toUtc();
          manifest[entry.key.toString()] = _ManifestEntry(
            checksum: checksum,
            updatedAt: updatedAt,
          );
        }
      }

      return _MirrorState(
        serverChangeToken: serverChangeToken,
        manifest: manifest,
      );
    } catch (_) {
      return const _MirrorState();
    }
  }

  Future<void> _persistMirrorState() async {
    if (_config?.dataMode != CloudKitDataMode.localMirror) {
      return;
    }

    final statePath = _mirrorStatePath();
    final stateFile = File(statePath);
    final stateDir = stateFile.parent;
    if (!stateDir.existsSync()) {
      await stateDir.create(recursive: true);
    }

    final tmpFile = File('$statePath.tmp');
    final manifest = <String, Map<String, Object?>>{};
    for (final entry in _mirrorState.manifest.entries) {
      manifest[entry.key] = <String, Object?>{
        'checksum': entry.value.checksum,
        'updatedAt': entry.value.updatedAt.toUtc().toIso8601String(),
      };
    }

    final payload = <String, Object?>{
      'schemaVersion': _stateSchemaVersion,
      'serverChangeToken': _mirrorState.serverChangeToken,
      'manifest': manifest,
    };

    await tmpFile.writeAsString(jsonEncode(payload), flush: true);
    try {
      await tmpFile.rename(statePath);
    } on FileSystemException {
      // Windows/filesystem fallback when rename over existing file isn't
      // supported; keeps previous state until new content is written.
      await stateFile.writeAsString(await tmpFile.readAsString(), flush: true);
      if (tmpFile.existsSync()) {
        await tmpFile.delete();
      }
    }
  }

  Future<Map<String, _ManifestEntry>> _buildManifestFromLocalMirror() async {
    final localFiles = await _readLocalMirrorFiles();
    final manifest = <String, _ManifestEntry>{};
    for (final entry in localFiles.entries) {
      final checksum = normalizedSha256Hex(entry.value);
      final previous = _mirrorState.manifest[entry.key];
      manifest[entry.key] = _ManifestEntry(
        checksum: checksum,
        updatedAt: previous != null && previous.checksum == checksum
            ? previous.updatedAt
            : DateTime.now().toUtc(),
      );
    }
    return manifest;
  }

  Future<Map<String, String>> _readLocalMirrorFiles() async {
    final config = _config?.localMirrorConfig;
    if (config == null) {
      return const <String, String>{};
    }

    final root = Directory(config.basePath);
    if (!root.existsSync()) {
      return const <String, String>{};
    }

    final files = <String, String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final relativePath = path
          .relative(entity.path, from: config.basePath)
          .replaceAll(r'\', '/');
      if (relativePath.startsWith('.us/')) {
        continue;
      }
      files[relativePath] = await entity.readAsString();
    }

    return files;
  }

  String _mirrorStatePath() {
    final config = _config?.localMirrorConfig;
    if (config == null) {
      throw const ConfigurationException(
        'CloudKit localMirror state requested without localMirrorConfig.',
      );
    }
    return path.join(config.basePath, _stateRelativePath);
  }

  void _ensureInitialized() {
    if (!_initialized || _config == null) {
      throw const AuthenticationException(
        'CloudKit provider not initialized. Call initWithConfig() first.',
      );
    }
  }

  String _normalizePath(final String filePath) {
    final normalized = filePath
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('/+'), '/')
        .replaceAll(RegExp('^/+'), '')
        .replaceAll(RegExp(r'/+$'), '')
        .trim();
    if (normalized.isEmpty || normalized == '.') {
      throw ArgumentError('filePath cannot be empty');
    }
    return normalized;
  }

  String _normalizePrefix(final String directoryPath) {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      return '';
    }
    return trimmed
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('/+'), '/')
        .replaceAll(RegExp('^/+'), '')
        .replaceAll(RegExp(r'/+$'), '');
  }

  ConflictResolutionStrategy _parseStrategy(final String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return ConflictResolutionStrategy.clientAlwaysRight;
    }

    return ConflictResolutionStrategy.values.firstWhere(
      (final strategy) => strategy.name == raw,
      orElse: () => ConflictResolutionStrategy.clientAlwaysRight,
    );
  }

  String _platformLabel() {
    if (identical(0, 0.0)) {
      return 'web';
    }

    if (Platform.isIOS) {
      return 'ios';
    }
    if (Platform.isMacOS) {
      return 'macos';
    }
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isLinux) {
      return 'linux';
    }

    return 'unknown';
  }

  static _LocalMirrorStore _defaultLocalMirrorFactory() => _LocalMirrorStore();
}

class _LocalMirrorStore {
  _LocalMirrorStore();

  late FileSystemConfig _config;
  var _initialized = false;

  Future<void> init(final FileSystemConfig config) async {
    _config = config;
    final root = Directory(_config.basePath);
    if (!root.existsSync()) {
      await root.create(recursive: true);
    }
    _initialized = true;
  }

  Future<FileOperationResult> createFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    final normalizedPath = _normalizePath(filePath);
    final file = _resolveFile(normalizedPath);
    if (file.existsSync()) {
      throw FileAlreadyExistsException(
        'File already exists at path: $filePath',
      );
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);

    return FileOperationResult.created(path: normalizedPath);
  }

  Future<FileOperationResult> updateFile(
    final String filePath,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    final normalizedPath = _normalizePath(filePath);
    final file = _resolveFile(normalizedPath);
    if (!file.existsSync()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }
    await file.writeAsString(content, flush: true);
    return FileOperationResult.updated(path: normalizedPath);
  }

  Future<FileOperationResult> deleteFile(
    final String filePath, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    final normalizedPath = _normalizePath(filePath);
    final file = _resolveFile(normalizedPath);
    if (!file.existsSync()) {
      throw FileNotFoundException('File not found at path: $filePath');
    }
    await file.delete();
    return FileOperationResult.deleted(path: normalizedPath);
  }

  Future<String?> getFile(final String filePath) async {
    _ensureInitialized();
    final normalizedPath = _normalizePath(filePath);
    final file = _resolveFile(normalizedPath);
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsString();
  }

  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();
    final normalizedPath = _normalizeDirectory(directoryPath);
    final directory = normalizedPath.isEmpty
        ? Directory(_config.basePath)
        : Directory(path.join(_config.basePath, normalizedPath));
    if (!directory.existsSync()) {
      return const <FileEntry>[];
    }

    final entries = <FileEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      final stat = await entity.stat();
      final name = path.basename(entity.path);
      entries.add(
        FileEntry(
          name: name,
          isDirectory: entity is Directory,
          size: entity is File ? stat.size : 0,
          modifiedAt: stat.modified.toUtc(),
        ),
      );
    }
    entries.sort((final a, final b) => a.name.compareTo(b.name));
    return entries;
  }

  Future<void> dispose() async {
    _initialized = false;
  }

  File _resolveFile(final String normalizedPath) =>
      File(path.join(_config.basePath, normalizedPath));

  void _ensureInitialized() {
    if (!_initialized) {
      throw const AuthenticationException(
        'CloudKit local mirror store is not initialized.',
      );
    }
  }

  String _normalizePath(final String filePath) {
    final normalized = filePath
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('/+'), '/')
        .replaceAll(RegExp('^/+'), '')
        .replaceAll(RegExp(r'/+$'), '')
        .trim();
    if (normalized.isEmpty || normalized == '.') {
      throw ArgumentError('filePath cannot be empty');
    }
    return normalized;
  }

  String _normalizeDirectory(final String directoryPath) {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty || trimmed == '.') {
      return '';
    }
    return trimmed
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('/+'), '/')
        .replaceAll(RegExp('^/+'), '')
        .replaceAll(RegExp(r'/+$'), '');
  }
}

class _MirrorState {
  const _MirrorState({
    this.serverChangeToken,
    this.manifest = const <String, _ManifestEntry>{},
  });

  final String? serverChangeToken;
  final Map<String, _ManifestEntry> manifest;

  _MirrorState copyWith({
    final String? serverChangeToken,
    final Map<String, _ManifestEntry>? manifest,
  }) => _MirrorState(
    serverChangeToken: serverChangeToken ?? this.serverChangeToken,
    manifest: manifest ?? this.manifest,
  );

  _MirrorState withManifestEntry(
    final String path,
    final _ManifestEntry entry,
  ) {
    final next = Map<String, _ManifestEntry>.from(manifest);
    next[path] = entry;
    return copyWith(manifest: next);
  }

  _MirrorState withoutManifestEntry(final String path) {
    final next = Map<String, _ManifestEntry>.from(manifest);
    next.remove(path);
    return copyWith(manifest: next);
  }
}

class _ManifestEntry {
  const _ManifestEntry({required this.checksum, required this.updatedAt});

  final String checksum;
  final DateTime updatedAt;
}
