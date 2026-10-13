import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:universal_io/io.dart';

import 'live_apply_exceptions.dart';
import 'live_apply_models.dart';

export 'live_apply_models.dart' show liveApplyDeletedSha256;

/// SHA-256 (hex) of UTF-8 [content].
String liveApplySha256(final String content) =>
    crypto.sha256.convert(utf8.encode(content)).toString();

/// On-disk store for run journals: `<storePath>/undo/<runId>/journal.json`.
///
/// The journal lives on the LOCAL filesystem even when the wrapped provider
/// is remote — it is the device's own undo log, not replicated state.
/// Writes are atomic (temp file + rename) so a crash mid-write leaves the
/// previous journal intact.
class LiveApplyJournalStore {
  /// Store rooted at the local journal directory.
  LiveApplyJournalStore({required this.storePath});

  static final Set<String> _activeStores = <String>{};

  /// Cooperating callers serialize one complete check/journal/effect sequence.
  /// The lock inode is retained. Bypassing providers need host writer
  /// exclusion.
  Future<T> withExclusive<T>(final Future<T> Function() action) async {
    await ensureRoot();
    final key = await Directory(storePath).resolveSymbolicLinks();
    if (!_activeStores.add(key)) {
      throw const LiveApplyRefusalException(
        'live-apply store has an active writer',
      );
    }
    RandomAccessFile? lock;
    var locked = false;
    try {
      lock = await File(p.join(key, 'writer.lock')).open(mode: FileMode.append);
      try {
        await lock.lock();
        locked = true;
      } on FileSystemException {
        throw const LiveApplyRefusalException(
          'live-apply store has an active writer',
        );
      }
      return await action();
    } finally {
      try {
        if (locked) await lock!.unlock();
      } finally {
        try {
          await lock?.close();
        } finally {
          _activeStores.remove(key);
        }
      }
    }
  }

  /// Directory under which undo runs are kept.
  final String storePath;

  Directory get _runsRoot => Directory(p.join(storePath, 'undo'));

  /// Directory holding the retained run.
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
    } on FormatException catch (error) {
      throw LiveApplyRefusalException('invalid journal $runId: $error');
      // Malformed persisted JSON is external data, not a programming error.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw LiveApplyRefusalException('invalid journal $runId: $error');
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
