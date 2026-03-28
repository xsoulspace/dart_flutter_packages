import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';
import 'package:xsoulspace_logger_triage/xsoulspace_logger_triage.dart';

/// Coordinates inspection state across logs, traces, and issues.
final class LoggerInspectorController extends ChangeNotifier {
  LoggerInspectorController({
    required this.logger,
    this.triage,
    this.initialQuery = const LogQuery(),
    this.issueLimit = 50,
    this.maxLogItems = 2000,
  });

  final Logger logger;
  final IssueTriageSink? triage;
  final LogQuery initialQuery;
  final int issueLimit;
  final int maxLogItems;

  LogQuery _query = const LogQuery();
  List<LogRecord> _logs = <LogRecord>[];
  List<LogRecord> _traceRecords = <LogRecord>[];
  List<IssueGroup> _issues = <IssueGroup>[];
  String? _selectedTraceId;

  StreamSubscription<LogRecord>? _logSubscription;
  StreamSubscription<List<IssueGroup>>? _issuesSubscription;

  bool _initialized = false;
  bool _loading = false;

  bool get isInitialized => _initialized;
  bool get isLoading => _loading;

  LogQuery get query => _query;
  List<LogRecord> get logs => List<LogRecord>.unmodifiable(_logs);
  List<LogRecord> get traceRecords =>
      List<LogRecord>.unmodifiable(_traceRecords);
  List<IssueGroup> get issues => List<IssueGroup>.unmodifiable(_issues);
  String? get selectedTraceId => _selectedTraceId;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    _query = initialQuery;
    await refresh();
    await _bindWatchers();
    _initialized = true;
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();

    _logs = await logger.query(_query);
    if (_logs.length > maxLogItems) {
      _logs = _logs.sublist(_logs.length - maxLogItems);
    }

    if (_selectedTraceId != null) {
      _traceRecords = await logger.trace(_selectedTraceId!);
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> setQuery(final LogQuery query) async {
    _query = query;
    await _logSubscription?.cancel();
    _logSubscription = logger.watch(_query).listen(_onLogRecord);
    await refresh();
  }

  Future<void> openTrace(final String traceId) async {
    _selectedTraceId = traceId;
    _traceRecords = await logger.trace(traceId);
    notifyListeners();
  }

  void clearTrace() {
    _selectedTraceId = null;
    _traceRecords = <LogRecord>[];
    notifyListeners();
  }

  Future<void> _bindWatchers() async {
    await _logSubscription?.cancel();
    _logSubscription = logger.watch(_query).listen(_onLogRecord);

    final triageSink = triage;
    if (triageSink != null) {
      await _issuesSubscription?.cancel();
      _issuesSubscription = triageSink.watchTopIssues(limit: issueLimit).listen(
        (final groups) {
          _issues = groups;
          notifyListeners();
        },
      );
    }
  }

  void _onLogRecord(final LogRecord record) {
    _logs = <LogRecord>[..._logs, record];
    if (_logs.length > maxLogItems) {
      _logs = _logs.sublist(_logs.length - maxLogItems);
    }

    final traceId = _selectedTraceId;
    if (traceId != null && record.trace?.traceId == traceId) {
      _traceRecords = <LogRecord>[..._traceRecords, record];
    }

    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_logSubscription?.cancel());
    unawaited(_issuesSubscription?.cancel());
    super.dispose();
  }
}
