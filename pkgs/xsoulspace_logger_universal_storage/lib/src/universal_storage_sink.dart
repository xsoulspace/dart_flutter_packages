library;

import 'dart:convert';

import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

import 'universal_storage_sink_config.dart';

/// StorageService-backed log sink with append + snapshot compaction.
final class UniversalStorageSink implements LogSink {
  UniversalStorageSink(
    this.service,
    this.namespacePath, {
    this.config = const UniversalStorageSinkConfig(),
  });

  final StorageService service;
  final String namespacePath;
  final UniversalStorageSinkConfig config;

  final List<LogRecord> _pending = <LogRecord>[];

  bool _initialized = false;
  bool _closed = false;
  bool _disposed = false;

  int _persistedSequence = 0;
  int _recordsSinceCompaction = 0;
  String _appendCache = '';

  String get _basePath => namespacePath.endsWith('/')
      ? namespacePath.substring(0, namespacePath.length - 1)
      : namespacePath;

  String get _appendPath => '$_basePath/${config.appendFileName}';
  String get _snapshotPath => '$_basePath/${config.snapshotFileName}';

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    final appendContent = await service.readFile(_appendPath);
    _appendCache = appendContent ?? '';

    var maxSequence = _maxSequenceFromNdjson(_appendCache);

    final snapshotContent = await service.readFile(_snapshotPath);
    final snapshot = _decodeSnapshot(snapshotContent);
    if (snapshot != null) {
      final rawLast = snapshot['lastSequence'];
      final snapshotLast = rawLast is num
          ? rawLast.toInt()
          : int.tryParse(rawLast?.toString() ?? '') ??
                _maxSequenceFromRecordMaps(_decodeSnapshotRecords(snapshot));
      if (snapshotLast > maxSequence) {
        maxSequence = snapshotLast;
      }
    }

    _persistedSequence = maxSequence;
    _initialized = true;
  }

  @override
  void enqueue(final LogRecord record) {
    if (_closed || _disposed) {
      return;
    }

    _pending.add(record);
  }

  @override
  Future<void> flush() async {
    if (_disposed) {
      return;
    }

    if (!_initialized) {
      await init();
    }

    if (_pending.isNotEmpty) {
      final batch = List<LogRecord>.from(_pending);
      _pending.clear();

      final buffer = StringBuffer(_appendCache);
      if (_appendCache.isNotEmpty && !_appendCache.endsWith('\n')) {
        buffer.writeln();
      }

      for (final record in batch) {
        final payload = Map<String, Object?>.from(
          record.toJson(
            schemaVersion: config.schemaVersion,
            maxStackTraceLines: config.persistedStackTraceLines,
          ),
        );

        _persistedSequence++;
        payload['coreSequence'] = record.sequence;
        payload['sequence'] = _persistedSequence;

        buffer.writeln(jsonEncode(payload));
      }

      _appendCache = buffer.toString();
      await service.saveFile(
        _appendPath,
        _appendCache,
        message: 'xsoulspace_logger append',
      );

      _recordsSinceCompaction += batch.length;
    }

    if (_recordsSinceCompaction >= config.compactionEvery) {
      await _compact();
    }
  }

  /// Compacts append records into the snapshot file and clears append.
  Future<void> compactNow() async {
    if (_disposed) {
      return;
    }
    if (!_initialized) {
      await init();
    }
    await _compact();
  }

  /// Restores records from last known-good snapshot.
  Future<List<LogRecord>> restoreLastKnownGoodSnapshot() async {
    if (!_initialized) {
      await init();
    }

    final snapshotContent = await service.readFile(_snapshotPath);
    final snapshot = _decodeSnapshot(snapshotContent);
    if (snapshot == null) {
      return const <LogRecord>[];
    }

    final recordMaps = _decodeSnapshotRecords(snapshot);
    return List<LogRecord>.unmodifiable(
      recordMaps.map(LogRecord.fromJson).toList(growable: false),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _closed = true;
    await flush();
    _disposed = true;
  }

  Future<void> _compact() async {
    final snapshotContent = await service.readFile(_snapshotPath);
    final snapshot = _decodeSnapshot(snapshotContent);
    final existingSnapshotRecords = snapshot == null
        ? <Map<String, Object?>>[]
        : _decodeSnapshotRecords(snapshot);
    final appendRecords = _decodeNdjsonRecords(_appendCache);

    final merged = <Map<String, Object?>>[
      ...existingSnapshotRecords,
      ...appendRecords,
    ];

    final kept = merged.length > config.snapshotMaxRecords
        ? merged.sublist(merged.length - config.snapshotMaxRecords)
        : merged;

    final snapshotPayload = <String, Object?>{
      'schemaVersion': config.schemaVersion,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'lastSequence': _persistedSequence,
      'recordCount': kept.length,
      'records': kept,
    };

    await service.saveFile(
      _snapshotPath,
      jsonEncode(snapshotPayload),
      message: 'xsoulspace_logger compact',
    );

    _appendCache = '';
    _recordsSinceCompaction = 0;

    await service.saveFile(_appendPath, '', message: 'xsoulspace_logger reset');
  }

  Map<String, Object?>? _decodeSnapshot(final String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<dynamic, dynamic>) {
        return Map<String, Object?>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, Object?>> _decodeSnapshotRecords(
    final Map<String, Object?> snapshot,
  ) {
    final raw = snapshot['records'];
    if (raw is! List) {
      return <Map<String, Object?>>[];
    }

    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((final row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  List<Map<String, Object?>> _decodeNdjsonRecords(final String content) {
    if (content.trim().isEmpty) {
      return <Map<String, Object?>>[];
    }

    final records = <Map<String, Object?>>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<dynamic, dynamic>) {
          records.add(Map<String, Object?>.from(decoded));
        }
      } catch (_) {
        // Ignore malformed append lines.
      }
    }

    return records;
  }

  int _maxSequenceFromNdjson(final String content) =>
      _maxSequenceFromRecordMaps(_decodeNdjsonRecords(content));

  int _maxSequenceFromRecordMaps(final List<Map<String, Object?>> records) {
    var maxSequence = 0;
    for (final row in records) {
      final rawSequence = row['sequence'];
      final sequence = rawSequence is num
          ? rawSequence.toInt()
          : int.tryParse(rawSequence?.toString() ?? '') ?? 0;
      if (sequence > maxSequence) {
        maxSequence = sequence;
      }
    }
    return maxSequence;
  }
}
