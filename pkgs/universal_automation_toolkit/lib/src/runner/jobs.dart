import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import '../plan/plan.dart';
import 'registry.dart';
import 'runner.dart';

/// Schema id of a persisted job record.
const jobRecordSchemaId = 'automation.job/v1';

/// One background job's record: submit-and-detach execution of a plan
/// (ADR 0064's resident job plane). The record persists on every
/// transition, so a serve restart keeps completed receipts readable;
/// queued-but-unstarted jobs do not survive a restart (a named
/// non-claim).
final class BackgroundJob {
  BackgroundJob._({
    required this.id,
    required this.planPath,
    required this.submittedAt,
    required this.status,
    this.scenario,
    this.overrides = const {},
    this.outDir,
    this.startedAt,
    this.finishedAt,
    this.report,
    this.errorKind,
    this.errorMessage,
  });

  /// Restores a record from its persisted JSON.
  factory BackgroundJob.fromJson(Map<String, Object?> json) => BackgroundJob._(
    id: json['id']! as String,
    planPath: json['plan']! as String,
    submittedAt: DateTime.parse(json['submittedAt']! as String),
    status: json['status']! as String,
    scenario: json['scenario'] as String?,
    overrides:
        (json['set'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry('$key', '$value'),
        ),
    outDir: json['out'] as String?,
    startedAt: json['startedAt'] is String
        ? DateTime.parse(json['startedAt']! as String)
        : null,
    finishedAt: json['finishedAt'] is String
        ? DateTime.parse(json['finishedAt']! as String)
        : null,
    report: json['report'] as Map<String, Object?>?,
    errorKind: json['errorKind'] as String?,
    errorMessage: json['errorMessage'] as String?,
  );

  /// `job-<epochMs>-<seq>` — unique per queue instance, sortable.
  final String id;

  /// The plan document the job runs.
  final String planPath;

  /// Scenario name inside the plan, when pinned.
  final String? scenario;

  /// Session handle overrides (`--set` shape).
  final Map<String, String> overrides;

  /// Output directory for screenshots and behavior receipts.
  final String? outDir;

  final DateTime submittedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// `queued` → `running` → `succeeded` | `failed`.
  final String status;

  /// The full run report, present when [status] is `succeeded`/`failed`.
  final Map<String, Object?>? report;

  /// Error category, when the job failed before a report existed.
  final String? errorKind;

  /// Error message, when the job failed before a report existed.
  final String? errorMessage;

  /// Copy with replacements (records are treated as immutable).
  BackgroundJob copyWith({
    String? status,
    DateTime? startedAt,
    DateTime? finishedAt,
    Map<String, Object?>? report,
    String? errorKind,
    String? errorMessage,
  }) => BackgroundJob._(
    id: id,
    planPath: planPath,
    submittedAt: submittedAt,
    status: status ?? this.status,
    scenario: scenario,
    overrides: overrides,
    outDir: outDir,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    report: report ?? this.report,
    errorKind: errorKind ?? this.errorKind,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  Map<String, Object?> toJson() => {
    'schema': jobRecordSchemaId,
    'id': id,
    'plan': planPath,
    if (scenario != null) 'scenario': scenario,
    if (overrides.isNotEmpty) 'set': overrides,
    if (outDir != null) 'out': outDir,
    'submittedAt': submittedAt.toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
    'status': status,
    if (report != null) 'report': report,
    if (errorKind != null) 'errorKind': errorKind,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };
}

/// Sequential, in-process executor with durable per-transition receipts
/// (ADR 0064): one desktop, one driver per anchor — jobs run FIFO and
/// never double-drive. [submit] returns immediately; [status] reads the
/// in-memory record or, after a restart, the persisted one.
final class JobQueue {
  /// Creates a queue persisting under [directory] (created lazily).
  /// [factories] passes through to each job's runner (the
  /// composition-root seam).
  JobQueue({required this.directory, this.factories});

  /// The jobs directory (`--jobs-dir`): one JSON record per job.
  final String directory;

  /// Per-transport driver factories each job's runner resolves with.
  final Map<AutomationTransport, DriverFactory>? factories;

  final Queue<BackgroundJob> _pending = Queue();
  final Map<String, BackgroundJob> _jobs = {};
  bool _draining = false;
  int _seq = 0;

  /// Jobs known in this process (completed receipts included).
  List<BackgroundJob> get jobs => List.unmodifiable(_jobs.values);

  /// Enqueues a plan run and returns its record (status `queued`)
  /// immediately. Execution starts on the next event-loop turn.
  BackgroundJob submit({
    required String planPath,
    String? scenario,
    Map<String, String> overrides = const {},
    String? outDir,
  }) {
    final job = BackgroundJob._(
      id: 'job-${DateTime.now().millisecondsSinceEpoch}-'
          '${_seq++}',
      planPath: planPath,
      submittedAt: DateTime.now().toUtc(),
      status: 'queued',
      scenario: scenario,
      overrides: overrides,
      outDir: outDir,
    );
    _jobs[job.id] = job;
    _pending.add(job);
    _persist(job);
    unawaited(_drain());
    return job;
  }

  /// The record for [jobId]: memory first, then the persisted receipts
  /// (readable across serve restarts).
  BackgroundJob? status(String jobId) =>
      _jobs[jobId] ?? _readPersisted(jobId);

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending.isNotEmpty) {
        await _runJob(_pending.removeFirst());
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _runJob(BackgroundJob queued) async {
    var job = queued.copyWith(status: 'running', startedAt: DateTime.now());
    _jobs[job.id] = job;
    _persist(job);
    try {
      final plan = await AutomationPlan.load(queued.planPath);
      final report = await PlanRunner(factories: factories).run(
        plan,
        scenarioName: queued.scenario,
        sessionOverrides: queued.overrides,
        outDir: queued.outDir,
      );
      job = job.copyWith(
        status: report.ok ? 'succeeded' : 'failed',
        finishedAt: DateTime.now(),
        report: report.toJson(),
      );
    } on AutomationException catch (error) {
      job = job.copyWith(
        status: 'failed',
        finishedAt: DateTime.now(),
        errorKind: error.kind,
        errorMessage: error.message,
      );
    } on FormatException catch (error) {
      job = job.copyWith(
        status: 'failed',
        finishedAt: DateTime.now(),
        errorKind: 'format',
        errorMessage: error.message,
      );
    } on FileSystemException catch (error) {
      job = job.copyWith(
        status: 'failed',
        finishedAt: DateTime.now(),
        errorKind: 'io',
        errorMessage: error.message,
      );
    }
    _jobs[job.id] = job;
    _persist(job);
  }

  File _fileOf(String jobId) {
    final name = jobId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return File('$directory/$name.json');
  }

  void _persist(BackgroundJob job) {
    try {
      final file = _fileOf(job.id);
      file.parent.createSync(recursive: true);
      // Temp + rename: a crash mid-write never leaves a torn record.
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(jsonEncode(job.toJson()), flush: true);
      temp.renameSync(file.path);
    } on FileSystemException {
      // Receipt persistence is best-effort; the in-memory record stays
      // authoritative for this process either way.
    }
  }

  BackgroundJob? _readPersisted(String jobId) {
    final file = _fileOf(jobId);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, Object?>) return null;
      return BackgroundJob.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }
}
