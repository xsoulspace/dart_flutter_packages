import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  test('absence and empty text have distinct valid permission states', () {
    expect(
      () => const StorageFileState(content: null, mode: null).validatePosix(),
      returnsNormally,
    );
    expect(
      () => const StorageFileState(content: '', mode: 0).validatePosix(),
      returnsNormally,
    );
    for (final mode in [0x180, 0x1a4, 0x1ed, 0x1ff]) {
      expect(
        () => StorageFileState(content: 'text', mode: mode).validatePosix(),
        returnsNormally,
      );
    }
  });

  test('missing, contradictory and special permissions refuse at runtime', () {
    for (final state in [
      const StorageFileState(content: 'text', mode: null),
      const StorageFileState(content: null, mode: 0x1a4),
      const StorageFileState(content: 'text', mode: -1),
      const StorageFileState(content: 'text', mode: 0x200),
      const StorageFileState(content: 'text', mode: 0xfff),
    ]) {
      expect(state.validatePosix, throwsFormatException);
    }
  });

  test('noninteger wire values cannot enter the typed mode contract', () {
    for (final Object value in [420.0, '0644', true]) {
      expect(
        () => StorageFileState(content: 'text', mode: value as dynamic),
        throwsA(isA<TypeError>()),
      );
    }
  });

  test('permission facet remains optional for existing provider contracts', () {
    final provider = _LegacyProvider();
    expect(provider, isA<StorageProvider>());
    expect(provider, isNot(isA<StorageFileStatePort>()));
    expect(storagePosixRwxProfile, 'posix-rwx-v1');
  });
}

class _LegacyProvider extends StorageProvider {
  @override
  Future<void> initWithConfig(StorageConfig config) async {}
  @override
  Future<bool> isAuthenticated() async => true;
  @override
  Future<String?> getFile(String path) async => null;
  @override
  Future<List<FileEntry>> listDirectory(String directoryPath) async => [];
  @override
  Future<FileOperationResult> createFile(
    String path,
    String content, {
    String? commitMessage,
  }) async => FileOperationResult.created(path: path);
  @override
  Future<FileOperationResult> updateFile(
    String path,
    String content, {
    String? commitMessage,
  }) async => FileOperationResult.updated(path: path);
  @override
  Future<FileOperationResult> deleteFile(
    String path, {
    String? commitMessage,
  }) async => FileOperationResult.deleted(path: path);
  @override
  Future<void> restore(String path, {String? versionId}) async {}
  @override
  Future<void> dispose() async {}
}
