import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  group('FileSystemStorageProvider', () {
    late FileSystemStorageProvider provider;
    late String tempDir;

    setUp(() async {
      // Create a temporary directory for testing
      final tempDirectory = await Directory.systemTemp.createTemp(
        'storage_test_',
      );
      tempDir = tempDirectory.path;

      provider = FileSystemStorageProvider();
      final config = FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: tempDir,
          macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
        ),
      );
      await provider.initWithConfig(config);
    });

    test('implements LocalEngine role for kernel profile routing', () {
      expect(provider, isA<LocalEngine>());
      expect(provider, isNot(isA<RemoteEngine>()));
    });

    tearDown(() async {
      // Clean up temporary directory
      final directory = Directory(tempDir);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('should save and read a file', () async {
      const filePath = 'test.txt';
      const content = 'Hello, World!';

      // Save file
      final savedResult = await provider.createFile(filePath, content);
      expect(savedResult.path, contains(filePath));

      // Read file
      final readContent = await provider.getFile(filePath);
      expect(readContent, equals(content));
    });

    test('should update an existing file', () async {
      const filePath = 'test.txt';
      const initialContent = 'Initial content';
      const updatedContent = 'Updated content';

      // Create initial file
      await provider.createFile(filePath, initialContent);

      // Update file
      await provider.updateFile(filePath, updatedContent);

      // Verify updated content
      final readContent = await provider.getFile(filePath);
      expect(readContent, equals(updatedContent));
    });

    test('should remove a file', () async {
      const filePath = 'test.txt';
      const content = 'Content to be deleted';

      // Create file
      await provider.createFile(filePath, content);

      // Verify file exists
      final contentBeforeDelete = await provider.getFile(filePath);
      expect(contentBeforeDelete, equals(content));

      // Remove file
      await provider.deleteFile(filePath);

      // Verify file is gone
      final contentAfterDelete = await provider.getFile(filePath);
      expect(contentAfterDelete, isNull);
    });

    test('should list files in directory', () async {
      // Create some test files
      await provider.createFile('file1.txt', 'Content 1');
      await provider.createFile('file2.txt', 'Content 2');
      await provider.createFile('subdir/file3.txt', 'Content 3');

      // List files in root directory
      final entries = await provider.listDirectory('.');
      final names = entries.map((final e) => e.name).toList();

      expect(names, contains('file1.txt'));
      expect(names, contains('file2.txt'));
      expect(names, contains('subdir'));
    });

    test('should return null for non-existent file', () async {
      final content = await provider.getFile('non_existent.txt');
      expect(content, isNull);
    });

    test('should throw exception when removing non-existent file', () {
      expect(
        () => provider.deleteFile('non_existent.txt'),
        throwsA(isA<FileNotFoundException>()),
      );
    });

    test('should handle nested directory creation', () async {
      const filePath = 'deep/nested/directory/file.txt';
      const content = 'Nested content';

      await provider.createFile(filePath, content);

      final readContent = await provider.getFile(filePath);
      expect(readContent, equals(content));
    });

    test('mutating operations return durability metadata', () async {
      final created = await provider.createFile(
        'settings/profile.json',
        '{"theme":"light"}',
      );
      final updated = await provider.updateFile(
        'settings/profile.json',
        '{"theme":"dark"}',
      );
      final deleted = await provider.deleteFile('settings/profile.json');

      for (final result in <FileOperationResult>[created, updated, deleted]) {
        expect(result.metadata['durability_protocol'], 'journal_v1');
        expect(result.metadata['durability_namespace'], isNotNull);
        expect(result.metadata['durability_operation_id'], isNotNull);
        expect(result.metadata['durability_sequence'], isA<int>());
      }
    });

    test(
      'serializes concurrent updates to the same path deterministically',
      () async {
        await provider.createFile('settings/race.json', '{"value":0}');
        final updates = List<Future<FileOperationResult>>.generate(
          20,
          (final index) =>
              provider.updateFile('settings/race.json', '{"value":$index}'),
        );
        await Future.wait(updates);
        final content = await provider.getFile('settings/race.json');
        expect(content, '{"value":19}');
      },
    );
  });

  group('FileSystemStorageProvider path access overrides', () {
    late Directory tempDirectory;
    late FilePathConfig filePathConfig;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'storage_path_access_test_',
      );
      filePathConfig = FilePathConfig.create(
        path: tempDirectory.path,
        macOSBookmarkData: MacOSBookmark.empty,
      );
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('calls custom resolver and release hooks', () async {
      final pathAccess = _RecordingPathAccess(tempDirectory);
      final provider = FileSystemStorageProvider(pathAccess: pathAccess);

      await provider.initWithConfig(
        FileSystemConfig(filePathConfig: filePathConfig),
      );

      expect(pathAccess.resolveCalls, 1);
      expect(pathAccess.lastResolvedPath, tempDirectory.path);

      await provider.dispose();
      expect(pathAccess.releaseCalls, 1);
      expect(pathAccess.lastReleasedPath, tempDirectory.path);
    });

    test('supports callback-based path access override', () async {
      var releaseCalls = 0;
      final provider = FileSystemStorageProvider(
        pathAccess: CallbackFileSystemPathAccess(
          resolveDirectory: (final config) async => Directory(config.path.path),
          releaseDirectory: (final config) async {
            releaseCalls++;
          },
        ),
      );

      await provider.initWithConfig(
        FileSystemConfig(filePathConfig: filePathConfig),
      );
      await provider.createFile('callback.txt', 'ok');
      expect(await provider.getFile('callback.txt'), 'ok');

      await provider.dispose();
      expect(releaseCalls, 1);
    });
  });

  group('FileSystemStorageProvider durability recovery', () {
    late String tempDir;
    late FilePathConfig filePathConfig;

    Future<FileSystemStorageProvider> createProvider() async {
      final provider = FileSystemStorageProvider();
      await provider.initWithConfig(
        FileSystemConfig(filePathConfig: filePathConfig),
      );
      return provider;
    }

    Map<String, dynamic> readRecoveryReport() {
      final reportFile = File(
        '$tempDir/.us/recovery/last_recovery_report.json',
      );
      expect(reportFile.existsSync(), isTrue);
      return Map<String, dynamic>.from(
        jsonDecode(reportFile.readAsStringSync()) as Map,
      );
    }

    setUp(() async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'storage_durability_test_',
      );
      tempDir = tempDirectory.path;
      filePathConfig = FilePathConfig.create(
        path: tempDir,
        macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
      );
    });

    tearDown(() async {
      final directory = Directory(tempDir);
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    test('replays prepared write from journal on startup', () async {
      const content = '{"recovered":true}';
      const operationId = 'settings_op_1';
      const relativePath = 'settings/recovered.json';
      final tempRelativePath = '.us/tmp/settings/$operationId.tmp';
      final tempFile = File('$tempDir/$tempRelativePath');
      await tempFile.parent.create(recursive: true);
      await tempFile.writeAsString(content, flush: true);

      final journalFile = File('$tempDir/.us/journal/settings.log');
      await journalFile.parent.create(recursive: true);
      await journalFile.writeAsString(
        '${jsonEncode(<String, dynamic>{'schema_version': 1, 'namespace': 'settings', 'operation_id': operationId, 'sequence': 1, 'operation_type': 'create', 'stage': 'prepared', 'relative_path': relativePath, 'timestamp_utc': DateTime.now().toUtc().toIso8601String(), 'temp_relative_path': tempRelativePath, 'checksum': normalizedSha256Hex(content), 'recovered': false})}\n',
        mode: FileMode.append,
        flush: true,
      );

      final provider = await createProvider();
      expect(await provider.getFile(relativePath), content);

      final report = readRecoveryReport();
      expect(report['abnormal_termination_detected'], isTrue);
      final totals = Map<String, dynamic>.from(report['totals'] as Map);
      expect(totals['replayed_operations'], 1);
      expect(totals['recovered_writes'], 1);

      await provider.dispose();
    });

    test('reports corrupted journal lines without crashing startup', () async {
      final journalFile = File('$tempDir/.us/journal/settings.log');
      await journalFile.parent.create(recursive: true);
      await journalFile.writeAsString(
        'this is not json\n'
        '${jsonEncode(<String, dynamic>{'schema_version': 1, 'namespace': 'settings', 'operation_id': 'valid_committed', 'sequence': 2, 'operation_type': 'update', 'stage': 'committed', 'relative_path': 'settings/ok.json', 'timestamp_utc': DateTime.now().toUtc().toIso8601String(), 'checksum': '', 'recovered': false})}\n',
        mode: FileMode.append,
        flush: true,
      );

      final provider = await createProvider();
      final report = readRecoveryReport();
      final totals = Map<String, dynamic>.from(report['totals'] as Map);
      expect(totals['corrupted_journal_entries'], 1);
      await provider.dispose();
    });

    test('recovery is idempotent across restarts', () async {
      const content = '{"idempotent":true}';
      const operationId = 'settings_op_2';
      const relativePath = 'settings/idempotent.json';
      final tempRelativePath = '.us/tmp/settings/$operationId.tmp';
      final tempFile = File('$tempDir/$tempRelativePath');
      await tempFile.parent.create(recursive: true);
      await tempFile.writeAsString(content, flush: true);

      final journalFile = File('$tempDir/.us/journal/settings.log');
      await journalFile.parent.create(recursive: true);
      await journalFile.writeAsString(
        '${jsonEncode(<String, dynamic>{'schema_version': 1, 'namespace': 'settings', 'operation_id': operationId, 'sequence': 10, 'operation_type': 'create', 'stage': 'prepared', 'relative_path': relativePath, 'timestamp_utc': DateTime.now().toUtc().toIso8601String(), 'temp_relative_path': tempRelativePath, 'checksum': normalizedSha256Hex(content), 'recovered': false})}\n',
        mode: FileMode.append,
        flush: true,
      );

      final provider1 = await createProvider();
      expect(await provider1.getFile(relativePath), content);
      final report1 = readRecoveryReport();
      expect(
        Map<String, dynamic>.from(
          report1['totals'] as Map,
        )['replayed_operations'],
        1,
      );
      await provider1.dispose();

      final provider2 = await createProvider();
      final report2 = readRecoveryReport();
      final totals2 = Map<String, dynamic>.from(report2['totals'] as Map);
      expect(totals2['replayed_operations'], 0);
      expect(totals2['duplicate_operations_skipped'], greaterThanOrEqualTo(1));
      await provider2.dispose();
    });
  });
}

final class _RecordingPathAccess implements FileSystemPathAccess {
  _RecordingPathAccess(this.directory);

  final Directory directory;
  int resolveCalls = 0;
  int releaseCalls = 0;
  String? lastResolvedPath;
  String? lastReleasedPath;

  @override
  Future<Directory?> resolveDirectory(final FilePathConfig config) async {
    resolveCalls++;
    lastResolvedPath = config.path.path;
    return directory;
  }

  @override
  Future<void> releaseDirectory(final FilePathConfig config) async {
    releaseCalls++;
    lastReleasedPath = config.path.path;
  }
}
