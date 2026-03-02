library;

import 'dart:async';
import 'dart:collection';

import 'log_level.dart';
import 'log_query.dart';
import 'log_record.dart';
import 'log_sink.dart';
import 'logger_categories.dart';
import 'logger_config.dart';
import 'trace_context.dart';

/// Core logger with deterministic single-writer dispatch and inspection APIs.
final class Logger {
  Logger(final LoggerConfig config, final List<LogSink> sinks)
    : _state = _LoggerState(
        config: config,
        sinks: List<LogSink>.unmodifiable(sinks),
      ),
      _defaultCategory = null,
      _defaultFields = const <String, Object?>{},
      _defaultTrace = null;

  Logger._child(
    this._state, {
    required final String? defaultCategory,
    required final Map<String, Object?> defaultFields,
    required final TraceContext? defaultTrace,
  }) : _defaultCategory = defaultCategory,
       _defaultFields = Map<String, Object?>.unmodifiable(defaultFields),
       _defaultTrace = defaultTrace;

  final _LoggerState _state;
  final String? _defaultCategory;
  final Map<String, Object?> _defaultFields;
  final TraceContext? _defaultTrace;

  LoggerConfig get config => _state.config;

  /// Optional explicit sink init.
  Future<void> init() => _state.ensureInitialized();

  /// Returns a child logger with merged context.
  Logger child({
    final String? category,
    final Map<String, Object?> fields = const <String, Object?>{},
    final TraceContext? trace,
  }) {
    final mergedFields = <String, Object?>{};
    if (_defaultFields.isNotEmpty) {
      mergedFields.addAll(_defaultFields);
    }
    if (fields.isNotEmpty) {
      mergedFields.addAll(fields);
    }

    return Logger._child(
      _state,
      defaultCategory: category ?? _defaultCategory,
      defaultFields: mergedFields,
      defaultTrace: trace ?? _defaultTrace,
    );
  }

  /// Runs [action] with a trace-scoped child logger.
  T withTrace<T>(
    final TraceContext trace,
    final T Function(Logger logger) action,
  ) => action(child(trace: trace));

  /// Async variant of [withTrace].
  Future<T> withTraceAsync<T>(
    final TraceContext trace,
    final Future<T> Function(Logger logger) action,
  ) => action(child(trace: trace));

  bool isEnabled(final LogLevel level) => level.isAtLeast(config.minLevel);

  /// Emits a structured log record.
  void log(
    final LogLevel level,
    final String category,
    final String message, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) {
    if (!isEnabled(level)) {
      return;
    }

    final effectiveCategory = category.isNotEmpty
        ? category
        : (_defaultCategory ?? LoggerCategories.app);

    final mergedFields = <String, Object?>{};
    if (_defaultFields.isNotEmpty) {
      mergedFields.addAll(_defaultFields);
    }
    if (fields.isNotEmpty) {
      mergedFields.addAll(fields);
    }

    final record = LogRecord(
      sequence: _state.nextSequence(),
      timestampUtc: config.clock.nowUtc(),
      level: level,
      category: effectiveCategory,
      message: message,
      fields: config.redaction.sanitizeFields(mergedFields),
      error: error,
      stackTrace: config.redaction.sanitizeStackTrace(stackTrace),
      trace: trace ?? _defaultTrace,
      fingerprint: null,
    );

    _state.enqueue(record);
    if (level == LogLevel.critical) {
      unawaited(_state.forceFlushAfterCritical());
    }
  }

  void traceLog(
    final String category,
    final String message, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) => log(
    LogLevel.trace,
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
    trace: trace,
  );

  void debug(
    final String category,
    final String message, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) => log(
    LogLevel.debug,
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
    trace: trace,
  );

  void info(
    final String category,
    final String message, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) => log(
    LogLevel.info,
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
    trace: trace,
  );

  void warning(
    final String category,
    final String message, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) => log(
    LogLevel.warning,
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
    trace: trace,
  );

  void error(
    final String category,
    final String message, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) => log(
    LogLevel.error,
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
    trace: trace,
  );

  void critical(
    final String category,
    final String message, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) => log(
    LogLevel.critical,
    category,
    message,
    fields: fields,
    error: error,
    stackTrace: stackTrace,
    trace: trace,
  );

  void traceLazy(
    final String category,
    final String Function() messageBuilder, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) {
    if (!isEnabled(LogLevel.trace)) {
      return;
    }
    traceLog(
      category,
      messageBuilder(),
      fields: fields,
      error: error,
      stackTrace: stackTrace,
      trace: trace,
    );
  }

  void debugLazy(
    final String category,
    final String Function() messageBuilder, {
    final Map<String, Object?> fields = const <String, Object?>{},
    final Object? error,
    final StackTrace? stackTrace,
    final TraceContext? trace,
  }) {
    if (!isEnabled(LogLevel.debug)) {
      return;
    }
    debug(
      category,
      messageBuilder(),
      fields: fields,
      error: error,
      stackTrace: stackTrace,
      trace: trace,
    );
  }

  Future<List<LogRecord>> query(final LogQuery query) => _state.query(query);

  Stream<LogRecord> watch(final LogQuery query) => _state.watch(query);

  Future<List<LogRecord>> traceQuery(final String traceId) =>
      _state.trace(traceId);

  /// Alias kept for plan naming compatibility.
  Future<List<LogRecord>> trace(final String traceId) => _state.trace(traceId);

  Future<void> flush() => _state.flush();

  Future<void> dispose() => _state.dispose();
}

final class _LoggerState {
  _LoggerState({required this.config, required final List<LogSink> sinks})
    : _sinks = sinks {
    _flushTimer = Timer.periodic(config.flushInterval, (_) {
      unawaited(flush());
    });
  }

  final LoggerConfig config;
  final List<LogSink> _sinks;
  final ListQueue<LogRecord> _pending = ListQueue<LogRecord>();
  final ListQueue<LogRecord> _history = ListQueue<LogRecord>();
  final StreamController<LogRecord> _streamController =
      StreamController<LogRecord>.broadcast();

  Timer? _flushTimer;
  bool _initialized = false;
  Completer<void>? _initCompleter;
  bool _draining = false;
  Completer<void>? _drainCompleter;
  bool _drainScheduled = false;
  bool _disposed = false;
  bool _closing = false;
  Future<void>? _disposeFuture;

  int _sequence = 1;
  int _recordsSinceLastFlush = 0;
  int _droppedRecordsSinceWarning = 0;
  DateTime? _lastBackpressureWarningAtUtc;

  int nextSequence() => _sequence++;

  void enqueue(final LogRecord record) {
    if (_disposed || _closing) {
      return;
    }

    if (!_canAccept(record)) {
      _registerDroppedRecord();
      return;
    }

    _pending.add(record);
    _scheduleDrain();
  }

  Future<void> forceFlushAfterCritical() => flush();

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    final existingCompleter = _initCompleter;
    if (existingCompleter != null) {
      return existingCompleter.future;
    }

    final completer = Completer<void>();
    _initCompleter = completer;

    try {
      for (final sink in _sinks) {
        await sink.init();
      }
      _initialized = true;
      completer.complete();
    } catch (error, stackTrace) {
      _initCompleter = null;
      completer.completeError(error, stackTrace);
      rethrow;
    }
  }

  Future<List<LogRecord>> query(final LogQuery query) async {
    final matches = _history
        .where((final record) => query.matches(record))
        .toList(growable: false);

    final limit = query.limit;
    if (limit == null || matches.length <= limit) {
      return List<LogRecord>.unmodifiable(matches);
    }

    return List<LogRecord>.unmodifiable(
      matches.sublist(matches.length - limit),
    );
  }

  Stream<LogRecord> watch(final LogQuery query) =>
      _streamController.stream.where(query.matches);

  Future<List<LogRecord>> trace(final String traceId) async {
    final records = (await query(LogQuery(traceId: traceId))).toList();
    records.sort((final a, final b) => a.sequence.compareTo(b.sequence));
    return List<LogRecord>.unmodifiable(records);
  }

  Future<void> flush() async {
    if (_disposed) {
      return;
    }

    final initialized = await _initializeForDrain();
    if (!initialized) {
      return;
    }

    await _runDrain();
    await _flushSinksSafely();
    _recordsSinceLastFlush = 0;
  }

  Future<void> dispose() {
    _disposeFuture ??= _disposeInternal();
    return _disposeFuture!;
  }

  Future<void> _disposeInternal() async {
    if (_disposed) {
      return;
    }

    _closing = true;
    _flushTimer?.cancel();

    try {
      await flush().timeout(config.disposeTimeout);
    } on TimeoutException {
      // Keep disposal deterministic even under sink stalls.
    }

    for (final sink in _sinks) {
      try {
        await sink.dispose();
      } catch (_) {
        // Sink failures are isolated.
      }
    }

    _disposed = true;
    if (!_streamController.isClosed) {
      await _streamController.close();
    }
  }

  bool _canAccept(final LogRecord incoming) {
    if (_pending.length < config.queueCapacity) {
      return true;
    }

    if (_pending.length >= config.hardQueueCapacity) {
      return false;
    }

    if (_isLowPriority(incoming.level)) {
      return false;
    }

    final dropped = _dropOneLowPriorityFromQueue();
    if (dropped) {
      _registerDroppedRecord();
      return true;
    }

    return _pending.length < config.hardQueueCapacity;
  }

  bool _isLowPriority(final LogLevel level) =>
      level == LogLevel.trace || level == LogLevel.debug;

  bool _dropOneLowPriorityFromQueue() {
    LogRecord? candidate;
    for (final record in _pending) {
      if (_isLowPriority(record.level)) {
        candidate = record;
        break;
      }
    }
    if (candidate != null) {
      _pending.remove(candidate);
      return true;
    }
    return false;
  }

  void _registerDroppedRecord() {
    _droppedRecordsSinceWarning++;
    _maybeEmitBackpressureWarning();
  }

  void _maybeEmitBackpressureWarning() {
    if (_droppedRecordsSinceWarning <= 0) {
      return;
    }

    final now = config.clock.nowUtc();
    final last = _lastBackpressureWarningAtUtc;
    if (last != null &&
        now.difference(last) < config.backpressureWarningInterval) {
      return;
    }

    _lastBackpressureWarningAtUtc = now;
    final droppedCount = _droppedRecordsSinceWarning;
    _droppedRecordsSinceWarning = 0;

    final warning = LogRecord(
      sequence: nextSequence(),
      timestampUtc: now,
      level: LogLevel.warning,
      category: LoggerCategories.backpressure,
      message: 'Dropping log records due to queue saturation.',
      fields: <String, Object?>{
        'dropped': droppedCount,
        'queueCapacity': config.queueCapacity,
        'hardQueueCapacity': config.hardQueueCapacity,
      },
    );

    _enqueueBackpressureWarning(warning);
  }

  void _enqueueBackpressureWarning(final LogRecord warning) {
    if (_disposed) {
      return;
    }

    if (_pending.length >= config.hardQueueCapacity) {
      if (!_dropOneLowPriorityFromQueue() && _pending.isNotEmpty) {
        _pending.removeFirst();
      }
    }

    if (_pending.length < config.hardQueueCapacity) {
      _pending.add(warning);
      _scheduleDrain();
    }
  }

  void _scheduleDrain() {
    if (_disposed || _drainScheduled) {
      return;
    }

    _drainScheduled = true;
    scheduleMicrotask(() {
      _drainScheduled = false;
      unawaited(_runDrain());
    });
  }

  Future<bool> _initializeForDrain() async {
    try {
      await ensureInitialized();
      return true;
    } catch (_) {
      _pending.clear();
      return false;
    }
  }

  Future<void> _runDrain() async {
    if (_disposed) {
      return;
    }

    final activeDrain = _drainCompleter;
    if (_draining && activeDrain != null) {
      await activeDrain.future;
      return;
    }

    final initialized = await _initializeForDrain();
    if (!initialized || _disposed) {
      return;
    }

    final completer = Completer<void>();
    _drainCompleter = completer;
    _draining = true;

    try {
      while (_pending.isNotEmpty) {
        final batch = <LogRecord>[];
        while (_pending.isNotEmpty && batch.length < config.flushBatchSize) {
          batch.add(_pending.removeFirst());
        }

        var containsCritical = false;
        for (final record in batch) {
          for (final sink in _sinks) {
            try {
              sink.enqueue(record);
            } catch (_) {
              // Sink enqueue errors are isolated.
            }
          }

          _appendHistory(record);
          if (!_streamController.isClosed) {
            _streamController.add(record);
          }

          _recordsSinceLastFlush++;
          if (record.level == LogLevel.critical) {
            containsCritical = true;
          }
        }

        if (_recordsSinceLastFlush >= config.flushBatchSize ||
            containsCritical) {
          await _flushSinksSafely();
          _recordsSinceLastFlush = 0;
        }
      }
    } finally {
      _draining = false;
      completer.complete();
      _drainCompleter = null;

      if (_pending.isNotEmpty && !_disposed) {
        _scheduleDrain();
      }
    }
  }

  Future<void> _flushSinksSafely() async {
    for (final sink in _sinks) {
      try {
        await sink.flush();
      } catch (_) {
        // Sink flush errors are isolated.
      }
    }
  }

  void _appendHistory(final LogRecord record) {
    _history.addLast(record);
    while (_history.length > config.historyCapacity) {
      _history.removeFirst();
    }
  }
}
