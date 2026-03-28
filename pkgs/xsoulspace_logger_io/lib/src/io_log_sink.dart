
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:xsoulspace_logger/xsoulspace_logger.dart';

import 'io_log_sink_config.dart';

/// Durable local-file sink using NDJSON segment files.
final class IoLogSink implements LogSink {
  IoLogSink(this.config) : _directory = Directory(config.directoryPath);

  final IoLogSinkConfig config;
  final Directory _directory;

  final List<LogRecord> _pendingRecords = <LogRecord>[];

  File? _activeSegment;
  RandomAccessFile? _activeRaf;
  int _activeSizeBytes = 0;
  int _segmentCounter = 0;

  int _recoveredMaxSequence = 0;
  DateTime _lastSyncAtUtc = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  bool _urgentSyncRequested = false;

  bool _initialized = false;
  Future<void>? _initFuture;
  bool _closed = false;
  bool _disposing = false;
  bool _disposed = false;

  /// Highest recovered/persisted sequence value.
  int get recoveredMaxSequence => _recoveredMaxSequence;

  /// Current writable segment.
  File? get activeSegmentFile => _activeSegment;

  @override
  Future<void> init() {
    _initFuture ??= _initInternal();
    return _initFuture!;
  }

  Future<void> _initInternal() async {
    await _directory.create(recursive: true);

    final segments = await _listSegments();
    if (segments.isEmpty) {
      await _openNewSegment();
      _initialized = true;
      return;
    }

    segments.sort((final a, final b) => a.path.compareTo(b.path));

    var maxSequence = await _recoverAndReadMaxSequence(segments.last);
    if (maxSequence == 0) {
      for (var i = segments.length - 2; i >= 0; i--) {
        maxSequence = await _readMaxSequence(segments[i]);
        if (maxSequence > 0) {
          break;
        }
      }
    }

    _recoveredMaxSequence = maxSequence;
    _activeSegment = segments.last;
    _activeSizeBytes = await _activeSegment!.length();
    _activeRaf = await _activeSegment!.open(mode: FileMode.append);

    await _enforceRetention();
    _initialized = true;
  }

  @override
  void enqueue(final LogRecord record) {
    if (_closed || _disposed) {
      return;
    }

    _pendingRecords.add(record);
    if (record.level.index >= LogLevel.warning.index) {
      _urgentSyncRequested = true;
    }
  }

  @override
  Future<void> flush() async {
    if (_disposed) {
      return;
    }

    if (!_initialized) {
      await init();
    }

    if (_activeRaf == null) {
      return;
    }

    if (_pendingRecords.isNotEmpty) {
      final batch = List<LogRecord>.from(_pendingRecords);
      _pendingRecords.clear();

      for (final record in batch) {
        final persisted = _toPersistedRecord(record);
        final line = '${jsonEncode(persisted)}\n';
        final encoded = utf8.encode(line);

        if (_activeSizeBytes + encoded.length > config.segmentMaxBytes) {
          await _rotateSegment();
        }

        await _activeRaf!.writeFrom(encoded);
        _activeSizeBytes += encoded.length;
      }
    }

    await _maybeSync();
  }

  @override
  Future<void> dispose() async {
    if (_disposed || _disposing) {
      return;
    }

    _disposing = true;
    _closed = true;

    try {
      await flush();

      final raf = _activeRaf;
      if (raf != null) {
        await raf.flush();
        await raf.close();
      }

      _activeRaf = null;
      _disposed = true;
    } finally {
      _disposing = false;
    }
  }

  Map<String, Object?> _toPersistedRecord(final LogRecord record) {
    final nextSequence = _recoveredMaxSequence + 1;
    _recoveredMaxSequence = nextSequence;

    final payload = Map<String, Object?>.from(
      record.toJson(
        schemaVersion: config.schemaVersion,
        maxStackTraceLines: config.persistedStackTraceLines,
      ),
    );

    payload['coreSequence'] = record.sequence;
    payload['sequence'] = nextSequence;
    return payload;
  }

  Future<void> _rotateSegment() async {
    final raf = _activeRaf;
    if (raf != null) {
      await raf.flush();
      await raf.close();
    }

    await _openNewSegment();
    await _enforceRetention();
  }

  Future<void> _openNewSegment() async {
    final nowMicros = DateTime.now()
        .toUtc()
        .microsecondsSinceEpoch
        .toString()
        .padLeft(20, '0');
    final counter = (_segmentCounter++).toString().padLeft(4, '0');
    final filename =
        '${config.segmentPrefix}$nowMicros$counter${config.segmentExtension}';

    final segment = File('${_directory.path}/$filename');
    await segment.create(recursive: true);

    _activeSegment = segment;
    _activeSizeBytes = await segment.length();
    _activeRaf = await segment.open(mode: FileMode.append);
  }

  Future<void> _maybeSync() async {
    final raf = _activeRaf;
    if (raf == null) {
      return;
    }

    final nowUtc = DateTime.now().toUtc();
    final due = nowUtc.difference(_lastSyncAtUtc) >= config.fsyncInterval;

    if (!_urgentSyncRequested && !due) {
      return;
    }

    await raf.flush();
    _lastSyncAtUtc = nowUtc;
    _urgentSyncRequested = false;
  }

  Future<int> _recoverAndReadMaxSequence(final File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      return 0;
    }

    var maxSequence = 0;
    var scanOffset = 0;
    var truncateOffset = bytes.length;

    while (scanOffset < bytes.length) {
      final lineEnd = bytes.indexOf(10, scanOffset);
      final end = lineEnd == -1 ? bytes.length : lineEnd;
      final lineBytes = bytes.sublist(scanOffset, end);
      final line = utf8.decode(lineBytes, allowMalformed: true).trim();

      if (line.isNotEmpty) {
        final sequence = _extractSequence(line);
        if (sequence == null) {
          truncateOffset = scanOffset;
          break;
        }
        maxSequence = max(maxSequence, sequence);
      }

      if (lineEnd == -1) {
        truncateOffset = bytes.length;
        break;
      }

      scanOffset = lineEnd + 1;
    }

    if (truncateOffset < bytes.length) {
      await file.writeAsBytes(
        bytes.sublist(0, truncateOffset),
        flush: true,
      );
    }

    return maxSequence;
  }

  Future<int> _readMaxSequence(final File file) async {
    final lines = await file.readAsLines();
    var maxSequence = 0;

    for (final line in lines) {
      final candidate = _extractSequence(line.trim());
      if (candidate != null) {
        maxSequence = max(maxSequence, candidate);
      }
    }

    return maxSequence;
  }

  int? _extractSequence(final String line) {
    if (line.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<dynamic, dynamic>) {
        return null;
      }

      final value = decoded['sequence'];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<File>> _listSegments() async {
    if (!_directory.existsSync()) {
      return <File>[];
    }

    final entities = await _directory.list().toList();
    return entities
        .whereType<File>()
        .where(
          (final file) =>
              file.path.endsWith(config.segmentExtension) &&
              file.uri.pathSegments.last.startsWith(config.segmentPrefix),
        )
        .toList();
  }

  Future<void> _enforceRetention() async {
    final nowUtc = DateTime.now().toUtc();

    var segments = await _listSegments();
    segments.sort((final a, final b) => a.path.compareTo(b.path));

    for (final segment in segments) {
      if (_isActiveSegment(segment)) {
        continue;
      }

      final stat = segment.statSync();
      if (nowUtc.difference(stat.modified.toUtc()) > config.retentionMaxAge) {
        await segment.delete();
      }
    }

    segments = await _listSegments();
    segments.sort((final a, final b) => a.path.compareTo(b.path));

    final sizeByPath = <String, int>{};
    var totalSize = 0;

    for (final segment in segments) {
      final size = await segment.length();
      sizeByPath[segment.path] = size;
      totalSize += size;
    }

    for (final segment in segments) {
      if (totalSize <= config.retentionMaxBytes) {
        break;
      }

      if (_isActiveSegment(segment) && segments.length > 1) {
        continue;
      }

      final size = sizeByPath[segment.path] ?? 0;
      await segment.delete();
      totalSize -= size;
    }
  }

  bool _isActiveSegment(final File file) =>
      _activeSegment != null && _activeSegment!.path == file.path;
}
