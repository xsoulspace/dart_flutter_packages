/// Journal data model: the footprint record that makes every applied run
/// invertible. Kept intentionally small and JSON-shaped so the journal can
/// later ride the mesh/replication layer as a proof-carrying delta.
library;

/// Prior state of one journaled path, captured before its first mutation.
class LiveApplyPrior {
  /// {@macro live_apply_prior}
  const LiveApplyPrior({required this.sha256, required this.content});

  /// SHA-256 of [content] (hex, lowercase).
  final String sha256;

  /// The full content before the run touched the path.
  final String content;

  /// Serialize the durable wire record.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'sha256': sha256,
    'content': content,
  };

  /// Read the durable wire record.
  // ignore: prefer_constructors_over_static_methods
  static LiveApplyPrior fromMap(final Map<String, dynamic> map) =>
      LiveApplyPrior(
        sha256: map['sha256'] as String,
        content: map['content'] as String,
      );
}

/// One journaled path: what was there before, and the content hash the run
/// left behind (the rollback window's drift check compares against it).
class LiveApplyEntry {
  /// {@macro live_apply_entry}
  LiveApplyEntry({
    required this.path,
    required this.postSha256,
    this.prior,
    this.postAbsent = false,
    this.pending = false,
    this.pendingPreSha256,
    this.inverseStarted = false,
    this.restored = false,
  });

  /// Provider path of the touched file.
  final String path;

  /// State before the run's first touch; `null` means the path did not
  /// exist — the inverse therefore deletes it.
  LiveApplyPrior? prior;

  /// SHA-256 of the intended/completed content. Presence is separate.
  String postSha256;

  /// True when the intended/completed post-state has no file.
  bool postAbsent;

  /// True until the dispatched provider effect is verified and checkpointed.
  bool pending;

  /// Null means absent before the pending operation; otherwise its hash.
  String? pendingPreSha256;

  /// Recovery may recognize either side of an interrupted inverse.
  bool inverseStarted;

  /// The recorded prior state has been verified and checkpointed.
  bool restored;

  /// Whether this run first touched an absent path.
  bool get wasAbsent => prior == null;

  /// Serialize the durable wire record.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'path': path,
    if (prior != null) 'prior': prior!.toMap(),
    'post_sha256': postSha256,
    'post_absent': postAbsent,
    'pending': pending,
    'pending_pre_sha256': pendingPreSha256,
    'inverse_started': inverseStarted,
    'restored': restored,
  };

  /// Read the durable wire record.
  // ignore: prefer_constructors_over_static_methods
  static LiveApplyEntry fromMap(final Map<String, dynamic> map) =>
      LiveApplyEntry(
        path: map['path'] as String,
        prior: map['prior'] == null
            ? null
            : LiveApplyPrior.fromMap(
                (map['prior'] as Map).cast<String, dynamic>(),
              ),
        postSha256: map['post_sha256'] as String,
        postAbsent: map['post_absent'] as bool? ?? false,
        pending: map['pending'] as bool? ?? false,
        pendingPreSha256: map['pending_pre_sha256'] as String?,
        inverseStarted: map['inverse_started'] as bool? ?? false,
        restored: map['restored'] as bool? ?? false,
      );
}

/// Lifecycle of a run. `open` runs are recoverable; `applied` runs sit in
/// the rollback window; `committed` runs are pruned; `rolled_back` runs are
/// retained as the audit record of the window.
enum LiveApplyRunStatus {
  /// Forward effects may be dispatched.
  open,

  /// Forward work completed; undo remains available.
  applied,

  /// Inverse replay may be resumed.
  rollingBack,

  /// Inverse verified; audit retained.
  rolledBack,

  /// Undo closed; journal may be pruned.
  committed,
}

/// The journal document for one run.
class LiveApplyJournal {
  /// {@macro live_apply_journal}
  LiveApplyJournal({
    required this.runId,
    required this.createdUtc,
    this.status = LiveApplyRunStatus.open,
    List<LiveApplyEntry>? entries,
  }) : entries = entries ?? <LiveApplyEntry>[];

  /// Unique id of the run.
  final String runId;

  /// UTC creation timestamp (ISO-8601).
  final String createdUtc;

  /// Lifecycle status.
  LiveApplyRunStatus status;

  /// Journaled paths, in first-touch order.
  final List<LiveApplyEntry> entries;

  /// Serialize the durable wire record.
  Map<String, dynamic> toMap() => <String, dynamic>{
    'run_id': runId,
    'schema_version': 2,
    'created_utc': createdUtc,
    'status': status.name,
    'entries': entries.map((final e) => e.toMap()).toList(),
  };

  /// Read the durable wire record.
  // ignore: prefer_constructors_over_static_methods
  static LiveApplyJournal fromMap(final Map<String, dynamic> map) {
    final version = map['schema_version'] ?? 1;
    if (version != 1 && version != 2) {
      throw const FormatException('unsupported live-apply journal version');
    }
    final rows = (map['entries'] as List?) ?? const [];
    if (version == 1 &&
        rows.any(
          (final e) =>
              (e as Map)['post_sha256'] ==
              ('e3b0c44298fc1c149afbf4c8996fb92427ae'
                  '41e4649b934ca495991b7852b855'),
        )) {
      throw const FormatException(
        'legacy journal has ambiguous empty/deleted state; '
        'reconcile explicitly',
      );
    }
    if (version == 2 &&
        rows.any(
          (final e) =>
              (e as Map)['post_absent'] is! bool ||
              e['pending'] is! bool ||
              e['inverse_started'] is! bool ||
              e['restored'] is! bool,
        )) {
      throw const FormatException('incomplete live-apply recovery state');
    }
    return LiveApplyJournal(
      runId: map['run_id'] as String,
      createdUtc: map['created_utc'] as String,
      status: LiveApplyRunStatus.values.firstWhere(
        (final s) => s.name == map['status'],
        orElse: () => throw const FormatException('unknown run status'),
      ),
      entries: ((map['entries'] as List?) ?? const [])
          .map(
            (final e) =>
                LiveApplyEntry.fromMap((e as Map).cast<String, dynamic>()),
          )
          .toList(),
    );
  }
}
