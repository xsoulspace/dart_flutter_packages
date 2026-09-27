import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

import 'live_apply_models.dart';

/// SHA-256 (hex) of UTF-8 [content].
String liveApplySha256(final String content) =>
    crypto.sha256.convert(utf8.encode(content)).toString();

/// Sentinel post-hash recorded for deletions (sha256 of the empty string).
const String liveApplyDeletedSha256 =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

/// On-disk store for run journals: `<storePath>/undo/<runId>/journal.json`.
///
/// The journal lives on the LOCAL filesystem even when the wrapped provider
/// is remote — it is the device's own undo log, not replicated state.
/// Writes are atomic (temp file + rename) so a crash mid-write leaves the
/// previous journal intact.
class LiveApplyJournalStore {
  /// {@macro live_apply_journal_store}
  LiveApplyJournalStore({required this.storePath});

  /// Directory under which undo runs are kept.
  final String storePath;

  Directory get _runsRoot =>
      Directory(p.join(storePath, 'undo'));

  Directory runDirectory(final String runId) =>
      Directory(p.join(_runsRoot.path, runId));

  File _journalFile(final String runId) =>
      File(p.join(runDirectory(runId).path, 'journal.json'));

  /// Creates the store root if missing.
  Future<void> ensureRoot() async {
    if (!_runsRoot.existsSync()) {
      await _runsRoot.create(recursive: true);
    }
  }

  /// Persists [journal] atomically.
  Future<void> write(final LiveApplyJournal journal) async {
    await ensureRoot();
    final file = _journalFile(journal.runId);
    final dir = file.parent;
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(journal.toMap()),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  /// Reads a run's journal, or `null` when the run does not exist.
  Future<LiveApplyJournal?> read(final String runId) async {
    final file = _journalFile(runId);
    if (!file.existsSync()) return null;
    try {
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return LiveApplyJournal.fromMap(decoded);
    } on FormatException {
      return null;
    }
  }

  /// Lists all runs, newest first.
  Future<List<LiveApplyJournal>> list() async {
    if (!_runsRoot.existsSync()) return const [];
    final runs = <LiveApplyJournal>[];
    final entries = _runsRoot.listSync();
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final journal = await read(p.basename(entry.path));
      if (journal != null) runs.add(journal);
    }
    runs.sort((final a, final b) => b.createdUtc.compareTo(a.createdUtc));
    return runs;
  }

  /// Deletes a run directory entirely (commit path).
  Future<void> prune(final String runId) async {
    final dir = runDirectory(runId);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}
