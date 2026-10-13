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
- **Write-ahead recovery** — schema v2 persists the pre-operation and intended
  post-operation presence/hash before dispatch. Interrupted effects recover only
  recognized states; unexplained drift refuses. Empty text and absence differ.
- **Restartable inverse** — `rollingBack` and per-path inverse progress persist
  around each restoration. Reopen resumes an interrupted inverse and verifies
  restored content or absence, including removal of newly created files.
- **Writer exclusion** — cooperating callers share a retained local store lock.
  Hosts must exclude writers bypassing that store; this is not provider CAS or
  distributed locking. Actual process-termination tests qualify POSIX recovery,
  not storage-hardware power-loss guarantees.

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

## Recovery compatibility (journal v2)

Unambiguous v1 journals remain readable. Legacy empty/deleted hash sentinels
are ambiguous and refuse with retained evidence; reconcile them explicitly.
Unknown versions, malformed state and unknown lifecycle values also refuse.
A failed provider call keeps its journal unless locked read-back proves the
entire footprint unchanged. An exception is not proof that nothing happened.

Direct callers use `mutate(path, intendedContent, effect)` for a single-path
provider effect: intent is persisted before dispatch and realized state is
verified afterward. The old `snapshot`/external-write/`recordPost` sequence is
unsafe; `recordPost` is deprecated and refuses. Native create/update/delete
exceptions and append behavior remain with the provider.

`markApplied` retains undo; `commit` explicitly finalizes and prunes it. Pending
or interrupted inverse work cannot finalize. Stale handles reload durable state
before dispatch. Hosts that verify after writing use `commit(requireApplied: true)`
to refuse finalization before the durable applied state under the same store lock.
The default preserves callers that finalize completed open work directly.
Multi-file rollback can be visible incrementally to readers;
it is restartable, not an atomic visibility transaction. See
[ADR 0062](../../docs/decisions/0062_live_apply_write_ahead_recovery.md).

## Permission-aware native recovery (journal v3)

Providers with the optional `StorageFileStatePort` declare a supported profile.
New qualified runs record prior, intended post and pending-pre modes alongside
presence/content hashes. Drift checks, settlement and inverse preflight compare
the complete declared state. The native POSIX provider restores bytes and mode
through its existing atomic publication, including private 0600 files.

Missing or incompatible capabilities refuse before effects. A metadata-aware
provider also refuses a legacy journal whose historical modes are missing;
it never guesses them from the current filesystem. Byte-only providers keep
their original v1/v2 compatibility. Existing journals are retained, not rewritten
or silently upgraded. See [ADR 0068](../../docs/decisions/0068_file_state_live_apply_recovery.md).

The initial profile covers POSIX rwx bits for readable regular files. It does
not preserve ACLs, ownership, timestamps, inode identity or arbitrary binary
effects. A complete batch can still be visible incrementally, and these
process-restart controls make no hardware power-loss claim.

### Native operation observations

Profile-qualified v3 entries optionally retain ordered `provider_receipts` from
actual returned provider results. Each selects the durability protocol, namespace,
sequence, operation ID and checkpoint sequence; the enclosing run/path and native
forward/inverse phase provide correlation. Arbitrary metadata is not persisted.
Legacy journals strip this unqualified extension. Each path permits 1024 receipts;
forward admission reserves one slot for the inverse and refuses before another
effect when capacity is exhausted.

These are post-effect observations, not grants, custody authentication or
write-ahead authorization. Missing or thrown results produce no invented receipt;
malformed advertised metadata leaves the durable pending state recoverable. A
crash or drift before the outer checkpoint can lose a returned receipt. Recognizing
already-restored source after restart does not imply a new provider operation.
Ordered IDs do not retain every intermediate source image, and a checkpoint may
truncate native rows. Independent custody observation remains necessary.
