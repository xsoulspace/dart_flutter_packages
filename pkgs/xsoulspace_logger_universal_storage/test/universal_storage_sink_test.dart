library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_universal_storage/xsoulspace_logger_universal_storage.dart';

void main() {
  group('UniversalStorageSink', () {
    test('appends NDJSON records with monotonic sequence', () async {
      final provider = _MemoryStorageProvider();
      final service = StorageService(provider);
      final sink = UniversalStorageSink(service, 'logger/runtime');

      final logger = Logger(
        const LoggerConfig(flushInterval: Duration(hours: 1)),
        <LogSink>[sink],
      );

      logger.info('api', 'one');
      logger.warning('api', 'two');

      await logger.flush();
      await logger.dispose();

      final append = provider.files['logger/runtime/append.ndjson'];
      expect(append, isNotNull);

      final lines = append!
          .split('\n')
          .where((final line) => line.trim().isNotEmpty)
          .toList(growable: false);
      expect(lines.length, 2);

      final first = jsonDecode(lines[0]) as Map<String, dynamic>;
      final second = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(first['sequence'], 1);
      expect(second['sequence'], 2);
      expect(first['coreSequence'], 1);
      expect(second['coreSequence'], 2);
    });

    test('compacts append log into snapshot and resets append', () async {
      final provider = _MemoryStorageProvider();
      final service = StorageService(provider);
      final sink = UniversalStorageSink(
        service,
        'logger/runtime',
        config: const UniversalStorageSinkConfig(compactionEvery: 2),
      );

      final logger = Logger(
        const LoggerConfig(flushInterval: Duration(hours: 1)),
        <LogSink>[sink],
      );

      logger.error('db', 'a');
      logger.error('db', 'b');
      logger.error('db', 'c');

      await logger.flush();

      final snapshotRaw = provider.files['logger/runtime/snapshot.json'];
      expect(snapshotRaw, isNotNull);

      final snapshot = jsonDecode(snapshotRaw!) as Map<String, dynamic>;
      final records = snapshot['records'] as List<dynamic>;
      expect(records.length, 3);
      expect(snapshot['lastSequence'], 3);

      expect(provider.files['logger/runtime/append.ndjson'], isEmpty);

      logger.warning('db', 'd');
      logger.warning('db', 'e');
      await logger.flush();

      final restored = await sink.restoreLastKnownGoodSnapshot();
      expect(restored.length, 5);
      expect(restored.last.message, 'e');

      await logger.dispose();
    });

    test(
      'restores snapshot and resumes sequence from preseeded data',
      () async {
        final provider = _MemoryStorageProvider();
        final service = StorageService(provider);

        final seedOne = LogRecord(
          sequence: 1,
          timestampUtc: DateTime.utc(2026, 1, 1),
          level: LogLevel.info,
          category: 'seed',
          message: 'one',
        ).toJson();
        seedOne['sequence'] = 1;

        final seedTwo = LogRecord(
          sequence: 2,
          timestampUtc: DateTime.utc(2026, 1, 1, 0, 0, 1),
          level: LogLevel.info,
          category: 'seed',
          message: 'two',
        ).toJson();
        seedTwo['sequence'] = 2;

        provider.files['logger/runtime/snapshot.json'] = jsonEncode(
          <String, Object?>{
            'schemaVersion': 1,
            'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
            'lastSequence': 2,
            'recordCount': 2,
            'records': <Map<String, Object?>>[seedOne, seedTwo],
          },
        );
        final appendSeed = <String, Object?>{
          'schemaVersion': 1,
          'sequence': 3,
          'coreSequence': 1,
          'timestampUtc': DateTime.utc(2026, 1, 1, 0, 0, 2).toIso8601String(),
          'level': 'info',
          'category': 'seed',
          'message': 'three',
          'fields': <String, Object?>{},
        };
        provider.files['logger/runtime/append.ndjson'] =
            '${jsonEncode(appendSeed)}\n';

        final sink = UniversalStorageSink(service, 'logger/runtime');
        await sink.init();

        final restored = await sink.restoreLastKnownGoodSnapshot();
        expect(restored.length, 2);
        expect(restored.first.message, 'one');

        final logger = Logger(
          const LoggerConfig(flushInterval: Duration(hours: 1)),
          <LogSink>[sink],
        );
        logger.info('seed', 'four');
        await logger.flush();
        await logger.dispose();

        final append = provider.files['logger/runtime/append.ndjson']!;
        final persisted = append
            .split('\n')
            .where((final line) => line.trim().isNotEmpty)
            .map((final line) => jsonDecode(line) as Map<String, dynamic>)
            .toList(growable: false);
        expect(persisted.last['sequence'], 4);
        expect(persisted.last['message'], 'four');
      },
    );
  });
}

final class _MemoryStorageProvider implements StorageProvider {
  final Map<String, String> files = <String, String>{};

  @override
  bool get supportsSync => false;

  @override
  Future<void> initWithConfig(final StorageConfig config) async {}

  @override
  Future<bool> isAuthenticated() async => true;

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    files[path] = content;
    return FileOperationResult.created(path: path);
  }

  @override
  Future<String?> getFile(final String path) async => files[path];

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    files[path] = content;
    return FileOperationResult.updated(path: path);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    files.remove(path);
    return FileOperationResult.deleted(path: path);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    final prefix = directoryPath.endsWith('/')
        ? directoryPath
        : '$directoryPath/';

    return files.keys
        .where((final path) => path.startsWith(prefix))
        .map(
          (final path) => FileEntry(
            name: path.substring(prefix.length),
            isDirectory: false,
            size: files[path]!.length,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> restore(final String path, {final String? versionId}) async {}

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {}

  @override
  Future<void> dispose() async {}
}
