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
  Future<void> initWithConfig(final StorageConfig config) async {}

  @override
  Future<bool> isAuthenticated() async => true;

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
      <FileEntry>[];

  @override
  Future<void> restore(final String path, {final String? versionId}) async {}

  @override
  bool get supportsSync => false;

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {}

  @override
  Future<void> dispose() async {}
}
