/// Journal data model: the footprint record that makes every applied run
/// invertible. Kept intentionally small and JSON-shaped so the journal can
/// later ride the mesh/replication layer as a proof-carrying delta.
library;

import 'package:universal_storage_interface/universal_storage_interface.dart'
    show StorageFileState, storagePosixRwxProfile;

import 'live_apply_provider_receipt.dart';

/// Legacy placeholder hash; schema v2 uses explicit presence for deletions.
const String liveApplyDeletedSha256 =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// Prior state of one journaled path, captured before its first mutation.
class LiveApplyPrior {
  /// {@macro live_apply_prior}
  const LiveApplyPrior({
    required this.sha256,
    required this.content,
    this.mode,
  });

  /// SHA-256 of [content] (hex, lowercase).
  final String sha256;

  /// The full content before the run touched the path.
  final String content;

  /// Recorded permission state, only qualified by a v3 journal profile.
  final int? mode;

  /// Serialize the durable wire record.
  Map<String, dynamic> toMap({final bool includeFileState = true}) =>
      <String, dynamic>{
        'sha256': sha256,
        'content': content,
        if (includeFileState) 'mode': mode,
      };

  /// Read the durable wire record.
  // ignore: prefer_constructors_over_static_methods
  static LiveApplyPrior fromMap(final Map<String, dynamic> map) =>
      LiveApplyPrior(
        sha256: map['sha256'] as String,
        content: map['content'] as String,
        mode: map['mode'] as int?,
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
    this.postMode,
    this.pendingPreMode,
    this.inverseStarted = false,
    this.restored = false,
    Iterable<LiveApplyProviderReceipt> providerReceipts = const [],
  }) : providerReceipts = List.of(providerReceipts);

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

  /// Intended post permission state; null when absent or legacy unqualified.
  int? postMode;

  /// Permission state before a pending effect; null when that state is absent.
  int? pendingPreMode;

  /// Recovery may recognize either side of an interrupted inverse.
  bool inverseStarted;

  /// The recorded prior state has been verified and checkpointed.
  bool restored;

  /// Actual provider observations in order, including repeated touches.
  final List<LiveApplyProviderReceipt> providerReceipts;

  /// Whether this run first touched an absent path.
  bool get wasAbsent => prior == null;

  /// Serialize the durable wire record.
  Map<String, dynamic> toMap({final bool includeFileState = true}) =>
      <String, dynamic>{
        'path': path,
        if (prior != null)
          'prior': prior!.toMap(includeFileState: includeFileState),
        'post_sha256': postSha256,
        'post_absent': postAbsent,
        'pending': pending,
        'pending_pre_sha256': pendingPreSha256,
        if (includeFileState) 'post_mode': postMode,
        if (includeFileState) 'pending_pre_mode': pendingPreMode,
        if (includeFileState && providerReceipts.isNotEmpty)
          'provider_receipts': _receiptMaps(providerReceipts),
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
        postMode: map['post_mode'] as int?,
        pendingPreMode: map['pending_pre_mode'] as int?,
        inverseStarted: map['inverse_started'] as bool? ?? false,
        restored: map['restored'] as bool? ?? false,
        providerReceipts: _readReceipts(map['provider_receipts']),
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
    this.fileStateProfile,
    List<LiveApplyEntry>? entries,
  }) : entries = entries ?? <LiveApplyEntry>[];

  /// Unique id of the run.
  final String runId;

  /// UTC creation timestamp (ISO-8601).
  final String createdUtc;

  /// Required native file-state facet. Null retains the legacy byte-only grade.
  final String? fileStateProfile;

  /// Lifecycle status.
  LiveApplyRunStatus status;

  /// Journaled paths, in first-touch order.
  final List<LiveApplyEntry> entries;

  /// Serialize legacy runs as v2; a profile-qualified run is v3. Metadata is
  /// never inferred from current files or silently added to legacy records.
  Map<String, dynamic> toMap() {
    final rows = entries
        .map((final e) => e.toMap(includeFileState: fileStateProfile != null))
        .toList();
    if (fileStateProfile != null) {
      _validateFileStateRows(fileStateProfile, rows);
    }
    return <String, dynamic>{
      'run_id': runId,
      'schema_version': fileStateProfile == null ? 2 : 3,
      if (fileStateProfile != null) 'file_state_profile': fileStateProfile,
      'created_utc': createdUtc,
      'status': status.name,
      'entries': rows,
    };
  }

  /// Read the durable wire record.
  // ignore: prefer_constructors_over_static_methods
  static LiveApplyJournal fromMap(final Map<String, dynamic> map) {
    final version = map['schema_version'] ?? 1;
    if (version != 1 && version != 2 && version != 3) {
      throw const FormatException('unsupported live-apply journal version');
    }
    if (version == 3 && map['entries'] is! List) {
      throw const FormatException('incomplete live-apply file-state entries');
    }
    final rows = (map['entries'] as List?) ?? const [];
    final profile = version == 3 ? map['file_state_profile'] : null;
    if (version == 3) {
      if (version is! int) {
        throw const FormatException('unsupported live-apply journal version');
      }
      _validateFileStateRows(profile, rows);
    }
    if (version == 1 &&
        rows.any(
          (final e) => (e as Map)['post_sha256'] == liveApplyDeletedSha256,
        )) {
      throw const FormatException(
        'legacy journal has ambiguous empty/deleted state; '
        'reconcile explicitly',
      );
    }
    if ((version == 2 || version == 3) &&
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
      fileStateProfile: profile as String?,
      status: LiveApplyRunStatus.values.firstWhere(
        (final s) => s.name == map['status'],
        orElse: () => throw const FormatException('unknown run status'),
      ),
      entries: ((map['entries'] as List?) ?? const [])
          .map(
            (final e) => LiveApplyEntry.fromMap(
              _entryMap(e as Map, fileState: version == 3),
            ),
          )
          .toList(),
    );
  }
}

Map<String, dynamic> _entryMap(Map row, {required bool fileState}) {
  final result = Map<String, dynamic>.from(row);
  if (!fileState) {
    result
      ..remove('post_mode')
      ..remove('pending_pre_mode')
      ..remove('provider_receipts');
    final prior = result['prior'];
    if (prior is Map) {
      result['prior'] = Map<String, dynamic>.from(prior)..remove('mode');
    }
  }
  return result;
}

void _validateFileStateRows(Object? profile, List rows) {
  if (profile != storagePosixRwxProfile) {
    throw const FormatException('unsupported live-apply file-state profile');
  }
  for (final raw in rows) {
    if (raw is! Map ||
        !raw.containsKey('post_mode') ||
        !raw.containsKey('pending_pre_mode') ||
        !raw.containsKey('pending_pre_sha256')) {
      throw const FormatException('incomplete live-apply file-state record');
    }
    final prior = raw['prior'];
    if (prior != null) {
      if (prior is! Map ||
          !prior.containsKey('mode') ||
          prior['content'] is! String) {
        throw const FormatException('incomplete live-apply prior file state');
      }
      _validateMode(prior['mode'], present: true);
    }
    if (raw['post_absent'] is! bool) {
      throw const FormatException('incomplete live-apply file-state presence');
    }
    _validateMode(raw['post_mode'], present: raw['post_absent'] == false);
    final preHash = raw['pending_pre_sha256'];
    if (preHash != null && preHash is! String) {
      throw const FormatException('invalid pending-pre content state');
    }
    _validateMode(raw['pending_pre_mode'], present: preHash != null);
  }
}

void _validateMode(Object? value, {required bool present}) {
  if (value != null && value is! int) {
    throw const FormatException('POSIX rwx mode must be an integer');
  }
  StorageFileState(
    content: present ? '' : null,
    mode: value as int?,
  ).validatePosix();
}

List<Map<String, dynamic>> _receiptMaps(
  List<LiveApplyProviderReceipt> receipts,
) {
  if (receipts.length > liveApplyMaxProviderReceipts) {
    throw const FormatException('live-apply provider receipt history limit');
  }
  return receipts.map((receipt) => receipt.toMap()).toList();
}

List<LiveApplyProviderReceipt> _readReceipts(Object? raw) {
  if (raw == null) return [];
  if (raw is! List || raw.length > liveApplyMaxProviderReceipts) {
    throw const FormatException('invalid live-apply provider receipt history');
  }
  return raw.map((item) {
    if (item is! Map || item.keys.any((key) => key is! String)) {
      throw const FormatException('invalid live-apply provider receipt');
    }
    return LiveApplyProviderReceipt.fromMap(Map<String, dynamic>.from(item));
  }).toList();
}
