import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_storage_db/universal_storage_db.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() {
  setUpAll(() {
    StorageProviderRegistry.register<FileSystemConfig>(
      _InMemoryStorageProvider.new,
    );
  });

  tearDownAll(StorageProviderRegistry.unregister<FileSystemConfig>);

  group('UniversalStorageDb + LocalDbUniversalStorageImpl', () {
    test('initializes storage service and authenticates provider', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);

      expect(await harness.db.storageService.isAuthenticated(), isTrue);
    });

    test('stores and reads primitive and map values', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final localDb = harness.localDb;

      await localDb.setBool(key: 'feature_enabled', value: true);
      await localDb.setInt(key: 'launch_count', value: 7);
      await localDb.setString(key: 'username', value: 'antonio');
      await localDb.setMap(
        key: 'profile',
        value: <String, dynamic>{'name': 'Antonio', 'age': 30},
      );

      expect(await localDb.getBool(key: 'feature_enabled'), isTrue);
      expect(await localDb.getInt(key: 'launch_count'), 7);
      expect(await localDb.getString(key: 'username'), 'antonio');
      expect(
        await localDb.getMap('profile'),
        <String, dynamic>{'name': 'Antonio', 'age': 30},
      );
    });

    test('stores and reads map-list values', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final localDb = harness.localDb;

      await localDb.setMapList(
        key: 'todos',
        value: <Map<String, dynamic>>[
          <String, dynamic>{'id': '1', 'title': 'A'},
          <String, dynamic>{'id': '2', 'title': 'B'},
        ],
      );

      final rows = await localDb.getMapIterable(key: 'todos');
      expect(rows, hasLength(2));
      expect(rows.first['id'], '1');
      expect(rows.last['id'], '2');
    });

    test('stores and reads string-list values', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final localDb = harness.localDb;

      await localDb.setStringList(
        key: 'tags',
        value: <String>['storage', 'kernel', 'sync'],
      );

      final values = await localDb.getStringsIterable(key: 'tags');
      expect(values.toList(), <String>['storage', 'kernel', 'sync']);
    });

    test('creates default single bool file on first read', () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      final localDb = harness.localDb;

      final value = await localDb.getBool(key: 'missing');
      expect(value, isFalse);

      expect(harness.provider.files.containsKey('xsun_b_single.json'), isTrue);
    });

    test('uses separate bool file routing when configured', () async {
      final harness = await _Harness.create(
        config: const UniversalStorageDbConfig(
          storageRouterTypes: StorageRouterType(placeBoolsToOneFile: false),
        ),
      );
      addTearDown(harness.dispose);
      final localDb = harness.localDb;

      await localDb.setBool(key: 'push_notifications', value: true);

      expect(
        harness.provider.files.containsKey('xsun_b_push_notifications.json'),
        isTrue,
      );
      expect(harness.provider.files.containsKey('xsun_b_single.json'), isFalse);
    });

    test('writes namespaced data under subfolder path', () async {
      final harness = await _Harness.create(subfolderPath: 'prefs/');
      addTearDown(harness.dispose);
      final localDb = harness.localDb;

      await localDb.setString(key: 'locale', value: 'en');

      expect(harness.provider.files.containsKey('prefs/xsun_s_single.json'), isTrue);
      expect(await localDb.getString(key: 'locale'), 'en');
    });
  });
}

class _Harness {
  _Harness._({
    required this.tempDir,
    required this.db,
    required this.localDb,
    required this.provider,
  });

  final Directory tempDir;
  final UniversalStorageDb db;
  final LocalDbUniversalStorageImpl localDb;
  final _InMemoryStorageProvider provider;

  static Future<_Harness> create({
    final UniversalStorageDbConfig config = const UniversalStorageDbConfig(),
    final String subfolderPath = '',
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('universal_db_test_');
    final db = UniversalStorageDb(
      storageConfig: FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: tempDir.path,
          macOSBookmarkData: MacOSBookmark.fromDirectory(tempDir),
        ),
      ),
      config: config,
    );
    await db.init();
    final localDb = LocalDbUniversalStorageImpl(
      db: db,
      subfolderPath: subfolderPath,
    );
    final provider = db.storageService.provider as _InMemoryStorageProvider;

    return _Harness._(
      tempDir: tempDir,
      db: db,
      localDb: localDb,
      provider: provider,
    );
  }

  Future<void> dispose() async {
    await db.storageService.provider.dispose();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _InMemoryStorageProvider extends StorageProvider {
  final Map<String, String> files = <String, String>{};
  var _initialized = false;

  void _ensureInitialized() {
    if (!_initialized) {
      throw const AuthenticationException(
        'Provider not initialized. Call initWithConfig first.',
      );
    }
  }

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! FileSystemConfig) {
      throw ArgumentError(
        'Expected FileSystemConfig, got ${config.runtimeType}',
      );
    }
    _initialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => _initialized;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    if (files.containsKey(path)) {
      throw FileAlreadyExistsException('File already exists at path: $path');
    }
    files[path] = content;
    return FileOperationResult.created(path: path);
  }

  @override
  Future<String?> getFile(final String path) async {
    _ensureInitialized();
    return files[path];
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    if (!files.containsKey(path)) {
      throw FileNotFoundException('File not found at path: $path');
    }
    files[path] = content;
    return FileOperationResult.updated(path: path);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    if (!files.containsKey(path)) {
      throw FileNotFoundException('File not found at path: $path');
    }
    files.remove(path);
    return FileOperationResult.deleted(path: path);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();
    return const <FileEntry>[];
  }

  @override
  Future<void> restore(final String path, {final String? versionId}) {
    throw const UnsupportedOperationException(
      'Restore operation is not supported by _InMemoryStorageProvider.',
    );
  }

  @override
  Future<void> dispose() async {
    files.clear();
    _initialized = false;
  }
}
