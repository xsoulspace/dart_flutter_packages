import 'package:test/test.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() {
  group('StorageFactory.createCloudKit', () {
    setUp(() {
      StorageProviderRegistry.register<CloudKitConfig>(
        _FakeCloudKitProvider.new,
      );
    });

    tearDown(() {
      StorageProviderRegistry.unregister<CloudKitConfig>();
    });

    test('creates service for CloudKitConfig', () async {
      final service = await StorageFactory.createCloudKit(
        CloudKitConfig(containerId: 'iCloud.com.example.app'),
      );

      expect(service.provider, isA<_FakeCloudKitProvider>());
    });
  });

  group('PathNormalizer cloudkit', () {
    test('normalizes cloudkit paths with forward slashes', () {
      final normalized = PathNormalizer.normalize(
        r'\root///folder\\file.txt//',
        ProviderType.cloudkit,
      );

      expect(normalized, equals('root/folder/file.txt'));
    });

    test('validates cloudkit path constraints', () {
      expect(
        PathNormalizer.isSafePath('docs/config.json', ProviderType.cloudkit),
        isTrue,
      );
      expect(
        PathNormalizer.isSafePath('../secret.txt', ProviderType.cloudkit),
        isFalse,
      );
      expect(
        PathNormalizer.isSafePath('.hidden/file', ProviderType.cloudkit),
        isFalse,
      );
    });
  });
}

class _FakeCloudKitProvider extends StorageProvider {
  bool initialized = false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! CloudKitConfig) {
      throw ArgumentError('Expected CloudKitConfig');
    }
    initialized = true;
  }

  @override
  Future<bool> isAuthenticated() async => initialized;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async => FileOperationResult.created(path: path);

  @override
  Future<String?> getFile(final String path) async => null;

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async => FileOperationResult.updated(path: path);

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async => FileOperationResult.deleted(path: path);

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async =>
      const <FileEntry>[];

  @override
  Future<void> restore(final String path, {final String? versionId}) async {}

  @override
  Future<void> dispose() async {
    initialized = false;
  }
}
