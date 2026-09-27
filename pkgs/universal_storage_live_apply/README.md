# universal_storage_live_apply

Live-apply transaction semantics for `universal_storage` providers: every
mutation applies **in place** but stays **provably undoable** until an
explicit commit. Git-free by design — no history DAG, no merge; a single
writer, a footprint journal, and a verified inverse.

## Model

- **Footprint journal** — before a path's first mutation in a run, its prior
  content (or absence) is recorded to
  `<journalStorePath>/undo/<runId>/journal.json`, along with the content
  hash the run leaves behind. Journals persist on the local filesystem even
  when the wrapped provider is remote: this is the device's own undo log,
  not replicated state.
- **Rollback window** — a retained run can be rolled back any time before
  commit. The inverse replays in reverse first-touch order and reads the
  result back to verify it.
- **Verified inverse** — rollback first checks that every journaled path
  still holds what the run left behind. External edits refuse the rollback
  (`LiveApplyDriftException` listing the paths) instead of being clobbered.
  Nothing is ever "approximately" restored.
- **Commit** — prunes the journal; the state is frozen. Rolled-back runs are
  retained as the audit record of the window.
- **Crash recovery** — a run whose journal exists but never finished is
  `open`; its journal alone is enough to `LiveApplyTransaction.reopen` and
  roll it back.

## Usage

```dart
// Per-operation: every mutation is one undoable run.
final live = LiveApplyStorageProvider(
  inner: FileSystemStorageProvider(),
  journalStorePath: '$home/.myapp/live_apply',
);
await live.initWithConfig(config);
await live.updateFile('doc.txt', 'v2');
await live.rollbackLast(); // doc.txt is 'v1' again
await live.commitLast();   // ...or freeze the change

// Batch: many operations, one journal, all-or-nothing.
final tx = await live.beginTransaction();
await tx.writeFile('a.txt', '...');
await tx.deleteFile('b.txt');
await tx.commit(); // or tx.rollback()
```

`createFile`/`updateFile`/`deleteFile` keep the interface's exact exception
semantics (already-exists / not-found) — the journal never blurs a failed
operation into a partial one.

## Deliberate limits (v0)

- **One run, one inverse.** A run's window covers its own post state; a
  later write over the same path invalidates an earlier run (the drift
  check refuses). Chained multi-run undo is a caller concern today.
- **Big files.** Prior contents are journaled inline (the interface's
  content domain is strings). `maxSnapshotFileBytes` refuses to journal a
  prior larger than the limit BEFORE mutating — the explicit big-file
  strategy rather than an unrestorable write. A content-addressed blob
  journal (hash-addressed snapshots outside the journal document) is the
  planned path to unbounded file sizes.
- **Not replication.** Convergence across devices belongs to the
  convergence/mesh layer. A committed run's journal is the natural
  proof-carrying delta for that transport: replicas can re-apply it and
  verify the same hashes locally.

## Design lineage

The mechanism mirrors codemap's live apply (ADR 0014 in the codemap repo):
footprint snapshot, journal-before-mutate, two-phase apply with verified
inverse replay, rollback window until commit.
