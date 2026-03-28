import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_io/xsoulspace_logger_io.dart';

void main() {
  group('IoLogSink', () {
    test('recovers from truncated tail and resumes sequence', () async {
      final temp = await Directory.systemTemp.createTemp('logger_io_recovery_');
      addTearDown(() => temp.delete(recursive: true));

      final file = File('${temp.path}/segment_00000000000000000001.ndjson');
      final seededRecord = <String, Object?>{
        'sequence': 41,
        'timestampUtc': DateTime.utc(2026).toIso8601String(),
        'level': 'info',
        'category': 'boot',
        'message': 'ok',
        'fields': <String, Object?>{},
      };
      await file.writeAsString('${jsonEncode(seededRecord)}\n{"sequence":42');

      final sink = IoLogSink(IoLogSinkConfig(directoryPath: temp.path));
      await sink.init();

      expect(sink.recoveredMaxSequence, 41);

      final repairedContent = await file.readAsString();
      expect(repairedContent.trim().endsWith('"sequence":42'), isFalse);

      final logger = Logger(
        const LoggerConfig(flushInterval: Duration(hours: 1)),
        <LogSink>[sink],
      );

      logger.info('io', 'after recovery');
      await logger.flush();
      await logger.dispose();

      final records = await _readPersistedRecords(temp);
      expect(records.last['sequence'], 42);
      expect(records.last['message'], 'after recovery');
    });

    test(
      'rotates segments under burst while preserving strict order',
      () async {
        final temp = await Directory.systemTemp.createTemp('logger_io_rotate_');
        addTearDown(() => temp.delete(recursive: true));

        final sink = IoLogSink(
          IoLogSinkConfig(
            directoryPath: temp.path,
            segmentMaxBytes: 350,
            retentionMaxBytes: 20 * 1024 * 1024,
          ),
        );

        final logger = Logger(
          const LoggerConfig(
            minLevel: LogLevel.trace,
            flushInterval: Duration(hours: 1),
            flushBatchSize: 1024,
            queueCapacity: 5000,
          ),
          <LogSink>[sink],
        );

        for (var i = 0; i < 200; i++) {
          logger.info(
            'burst',
            'message-$i',
            fields: <String, Object?>{'index': i},
          );
        }

        await logger.flush();
        await logger.dispose();

        final segments = await temp
            .list()
            .where((final entity) => entity is File)
            .cast<File>()
            .where((final file) => file.path.endsWith('.ndjson'))
            .toList();
        expect(segments.length, greaterThan(1));

        final records = await _readPersistedRecords(temp);
        expect(records.length, 200);

        final sequences = records
            .map((final row) => (row['sequence']! as num).toInt())
            .toList(growable: false);
        final unique = sequences.toSet();
        expect(unique.length, sequences.length);

        for (var i = 1; i < sequences.length; i++) {
          expect(sequences[i], greaterThan(sequences[i - 1]));
        }

        final coreSequences = records
            .map((final row) => (row['coreSequence']! as num).toInt())
            .toList(growable: false);
        expect(coreSequences.first, 1);
        expect(coreSequences.last, 200);
      },
    );

    test('evicts old segments by age on init', () async {
      final temp = await Directory.systemTemp.createTemp('logger_io_age_');
      addTearDown(() => temp.delete(recursive: true));

      final oldFile = File('${temp.path}/segment_00000000000000000001.ndjson');
      final newFile = File('${temp.path}/segment_00000000000000000099.ndjson');
      final oldRecord = <String, Object?>{
        'sequence': 1,
        'timestampUtc': DateTime.utc(2026).toIso8601String(),
        'level': 'info',
        'category': 'old',
        'message': 'old',
        'fields': <String, Object?>{},
      };
      final newRecord = <String, Object?>{
        'sequence': 2,
        'timestampUtc': DateTime.utc(2026, 1, 2).toIso8601String(),
        'level': 'info',
        'category': 'new',
        'message': 'new',
        'fields': <String, Object?>{},
      };

      await oldFile.writeAsString('${jsonEncode(oldRecord)}\n');
      await newFile.writeAsString('${jsonEncode(newRecord)}\n');

      oldFile.setLastModifiedSync(
        DateTime.now().toUtc().subtract(const Duration(days: 10)),
      );
      newFile.setLastModifiedSync(DateTime.now().toUtc());

      final sink = IoLogSink(
        IoLogSinkConfig(
          directoryPath: temp.path,
          retentionMaxBytes: 10 * 1024 * 1024,
        ),
      );

      await sink.init();
      await sink.dispose();

      expect(oldFile.existsSync(), isFalse);
      expect(newFile.existsSync(), isTrue);
    });

    test('enforces retention size while keeping newest data', () async {
      final temp = await Directory.systemTemp.createTemp('logger_io_size_');
      addTearDown(() => temp.delete(recursive: true));

      final sink = IoLogSink(
        IoLogSinkConfig(
          directoryPath: temp.path,
          segmentMaxBytes: 300,
          retentionMaxBytes: 800,
          retentionMaxAge: const Duration(days: 30),
        ),
      );

      final logger = Logger(
        const LoggerConfig(
          flushInterval: Duration(hours: 1),
          flushBatchSize: 2048,
          queueCapacity: 10000,
        ),
        <LogSink>[sink],
      );

      for (var i = 0; i < 300; i++) {
        logger.info('retention', 'payload-${'x' * 80}-$i');
      }

      await logger.flush();
      await logger.dispose();

      final segments = await temp
          .list()
          .where((final entity) => entity is File)
          .cast<File>()
          .where((final file) => file.path.endsWith('.ndjson'))
          .toList();

      int totalSize = 0;
      for (final segment in segments) {
        totalSize += await segment.length();
      }

      expect(totalSize, lessThanOrEqualTo(1100));
      expect(segments, isNotEmpty);
    });
  });
}

Future<List<Map<String, Object?>>> _readPersistedRecords(
  final Directory directory,
) async {
  final files = await directory
      .list()
      .where((final entity) => entity is File)
      .cast<File>()
      .where((final file) => file.path.endsWith('.ndjson'))
      .toList();

  files.sort((final a, final b) => a.path.compareTo(b.path));

  final rows = <Map<String, Object?>>[];
  for (final file in files) {
    final lines = await file.readAsLines();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      rows.add(
        Map<String, Object?>.from(jsonDecode(trimmed) as Map<dynamic, dynamic>),
      );
    }
  }

  return rows;
}
