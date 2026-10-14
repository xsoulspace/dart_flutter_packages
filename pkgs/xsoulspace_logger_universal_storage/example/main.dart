import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_universal_storage/xsoulspace_logger_universal_storage.dart';

Future<void> main() async {
  // Replace with a real provider implementation from your project.
  final service = StorageService(_NoopStorageProvider());

  final sink = UniversalStorageSink(service, 'observability/logger');
  final logger = Logger(const LoggerConfig(), <LogSink>[sink]);

  logger.warning('example', 'Stored through StorageService adapter');

  await logger.flush();
  await logger.dispose();
}

final class _NoopStorageProvider implements StorageProvider {
  @override
  Future<void> initWithConfig(StorageConfig config) async {}

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<FileOperationResult> createFile(
    String path,
    String content, {
    String? commitMessage,
  }) async => FileOperationResult.created(path: path);

  @override
  Future<String?> getFile(String path) async => null;

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
  Future<List<FileEntry>> listDirectory(String directoryPath) async =>
      <FileEntry>[];

  @override
  Future<void> restore(String path, {String? versionId}) async {}

  @override
  bool get supportsSync => false;

  @override
  Future<void> sync({
    String? pullMergeStrategy,
    String? pushConflictStrategy,
  }) async {}

  @override
  Future<void> dispose() async {}
}
