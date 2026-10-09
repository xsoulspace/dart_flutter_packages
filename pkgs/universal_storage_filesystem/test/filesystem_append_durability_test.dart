import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

void main() {
  late FileSystemStorageProvider provider;
  late String tempDir;

  setUp(() async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'storage_append_test_',
    );
    tempDir = tempDirectory.path;
    provider = FileSystemStorageProvider();
    await provider.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: tempDir,
          macOSBookmarkData: MacOSBookmark.fromDirectory(tempDirectory),
        ),
      ),
    );
  });

  tearDown(() async {
    final directory = Directory(tempDir);
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  Future<FileSystemStorageProvider> reopenedProvider() async {
    final reopened = FileSystemStorageProvider();
    await reopened.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: tempDir,
          macOSBookmarkData: MacOSBookmark.fromDirectory(
            Directory(tempDir),
          ),
        ),
      ),
    );
    return reopened;
  }

  group('appendFile', () {
    test('creates a missing file with the chunk', () async {
      await provider.appendFile('logs/app.log', 'first\n');
      expect(await provider.getFile('logs/app.log'), equals('first\n'));
    });

    test('appends without rewriting prior content', () async {
      await provider.createFile('logs/app.log', 'head\n');
      await provider.appendFile('logs/app.log', 'mid\n');
      await provider.appendFile('logs/app.log', 'tail\n');
      expect(
        await provider.getFile('logs/app.log'),
        equals('head\nmid\ntail\n'),
      );
    });

    test('byte offsets survive multi-byte UTF-8 chunks', () async {
      // ñ + emoji: 1 + 4 bytes, so String length != byte length.
      await provider.createFile('logs/utf8.log', 'ñ');
      await provider.appendFile('logs/utf8.log', '🝳');
      await provider.appendFile('logs/utf8.log', 'ñ');
      expect(await provider.getFile('logs/utf8.log'), equals('ñ🝳ñ'));
    });

    test('empty chunk is a no-op', () async {
      await provider.createFile('logs/app.log', 'head\n');
      await provider.appendFile('logs/app.log', '');
      expect(await provider.getFile('logs/app.log'), equals('head\n'));
    });

    test('StorageService.appendFile reaches the provider append', () async {
      final service = StorageService(provider);
      await service.appendFile('logs/app.log', 'a\n');
      await service.appendFile('logs/app.log', 'b\n');
      expect(await service.readFile('logs/app.log'), equals('a\nb\n'));
    });
  });

  group('append crash recovery', () {
    test('prepared-but-uncommitted append replays from the temp copy',
        () async {
      const path = 'logs/crash.log';
      await provider.createFile(path, 'head\n');
      // Simulate a crash between the prepared journal entry and the byte
      // append: write the chunk to the temp path, journal it as prepared,
      // and leave the target untouched.
      final chunk = utf8.encode('tail\n');
      final operationId = 'logs:append:999:1791600000000000';
      final tempRelativePath = '.us/tmp/logs/$operationId.tmp';
      final targetTemp = File('$tempDir/$tempRelativePath');
      await targetTemp.parent.create(recursive: true);
      await targetTemp.writeAsBytes(chunk, flush: true);
      final journal = File('$tempDir/.us/journal/logs.log');
      await journal.parent.create(recursive: true);
      await journal.writeAsString(
        '${jsonEncode(<String, dynamic>{
          'schema_version': 1,
          'namespace': 'logs',
          'operation_id': operationId,
          'sequence': 999,
          'operation_type': 'append',
          'stage': 'prepared',
          'relative_path': path,
          'timestamp_utc': '2026-10-10T00:00:00.000Z',
          'temp_relative_path': tempRelativePath,
          'checksum': '',
          'recovered': false,
          'append_offset': utf8.encode('head\n').length,
          'append_size': chunk.length,
        })}\n',
        mode: FileMode.append,
        flush: true,
      );

      final reopened = await reopenedProvider();
      expect(
        await reopened.getFile(path),
        equals('head\ntail\n'),
      );
    });

    test('torn partial append truncates back and replays', () async {
      const path = 'logs/torn.log';
      final head = utf8.encode('head\n');
      final chunk = utf8.encode('tail\n');
      final target = File('$tempDir/$path');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(head, flush: true);
      // A torn append: only half the chunk landed.
      await target.writeAsBytes(chunk.sublist(0, 2), mode: FileMode.append);

      final operationId = 'logs:append:1000:1791600000000001';
      final tempRelativePath = '.us/tmp/logs/$operationId.tmp';
      final targetTemp = File('$tempDir/$tempRelativePath');
      await targetTemp.parent.create(recursive: true);
      await targetTemp.writeAsBytes(chunk, flush: true);
      final journal = File('$tempDir/.us/journal/logs.log');
      await journal.parent.create(recursive: true);
      await journal.writeAsString(
        '${jsonEncode(<String, dynamic>{
          'schema_version': 1,
          'namespace': 'logs',
          'operation_id': operationId,
          'sequence': 1000,
          'operation_type': 'append',
          'stage': 'prepared',
          'relative_path': path,
          'timestamp_utc': '2026-10-10T00:00:00.000Z',
          'temp_relative_path': tempRelativePath,
          'checksum': '',
          'recovered': false,
          'append_offset': head.length,
          'append_size': chunk.length,
        })}\n',
        mode: FileMode.append,
        flush: true,
      );

      final reopened = await reopenedProvider();
      expect(await reopened.getFile(path), equals('head\ntail\n'));
    });
  });

  group('journal truncation', () {
    test('boot truncates committed journals to empty', () async {
      await provider.createFile('logs/app.log', 'head\n');
      await provider.appendFile('logs/app.log', 'tail\n');
      final journal = File('$tempDir/.us/journal/logs.log');
      expect(journal.existsSync(), isTrue);
      expect(journal.lengthSync(), greaterThan(0));

      final reopened = await reopenedProvider();
      expect(await reopened.getFile('logs/app.log'), equals('head\ntail\n'));
      expect(journal.lengthSync(), equals(0));
    });
  });
}
