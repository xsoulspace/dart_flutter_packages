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

  Map<String, dynamic> toMap() => <String, dynamic>{
        'sha256': sha256,
        'content': content,
      };

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
    this.prior,
    required this.postSha256,
  });

  /// Provider path of the touched file.
  final String path;

  /// State before the run's first touch; `null` means the path did not
  /// exist — the inverse therefore deletes it.
  LiveApplyPrior? prior;

  /// SHA-256 of the content the run left at the path, or the empty-string
  /// hash sentinel for deletions.
  String postSha256;

  bool get wasAbsent => prior == null;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'path': path,
        if (prior != null) 'prior': prior!.toMap(),
        'post_sha256': postSha256,
      };

  static LiveApplyEntry fromMap(final Map<String, dynamic> map) =>
      LiveApplyEntry(
        path: map['path'] as String,
        prior: map['prior'] == null
            ? null
            : LiveApplyPrior.fromMap(
                (map['prior'] as Map).cast<String, dynamic>(),
              ),
        postSha256: map['post_sha256'] as String,
      );
}

/// Lifecycle of a run. `open` runs are recoverable; `applied` runs sit in
/// the rollback window; `committed` runs are pruned; `rolled_back` runs are
/// retained as the audit record of the window.
enum LiveApplyRunStatus { open, applied, rolledBack, committed }

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

  Map<String, dynamic> toMap() => <String, dynamic>{
        'run_id': runId,
        'created_utc': createdUtc,
        'status': status.name,
        'entries': entries.map((final e) => e.toMap()).toList(),
      };

  static LiveApplyJournal fromMap(final Map<String, dynamic> map) =>
      LiveApplyJournal(
        runId: map['run_id'] as String,
        createdUtc: map['created_utc'] as String,
        status: LiveApplyRunStatus.values.firstWhere(
          (final s) => s.name == map['status'],
          orElse: () => LiveApplyRunStatus.open,
        ),
        entries: ((map['entries'] as List?) ?? const [])
            .map((final e) =>
                LiveApplyEntry.fromMap((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}
