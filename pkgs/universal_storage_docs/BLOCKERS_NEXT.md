# Universal Storage: Next Blockers

Last updated: `2026-08-22`

This is the only canonical next-steps document for Universal Storage.

## Completed (this cycle)

1. **StorageKernel decomposition** — kernel split into
   `kernel/observation_hub.dart`, `kernel/outbox.dart`,
   `kernel/migration_coordinator.dart`; public API unchanged.
   Evidence: all 70 sync package tests pass.
2. **Conformance suite** — `universal_storage_conformance` package with
   shared behavioral scenarios; adopted by filesystem, local_db,
   git_offline, github_api (via in-process fake API), cloudkit (fake bridge).
   Caught and fixed real bugs: trailing-slash path normalization
   (filesystem, git_offline), silent no-op sync in local_db, relative-name
   listing contract (filesystem, git_offline).
3. **Capability model unification** — dead mixins removed
   (`RemoteSyncCapable`, `VersionControlCapable`, `AuthenticatedProvider`);
   `SyncAvailability` tri-state (`none` / `always` / `withRemoteConfig`)
   added to `StorageCapabilities`; git_offline declares
   `withRemoteConfig`.
4. **Migration manager fixes** — plan metadata fallbacks (`overwrite`,
   `dry_run`, `collect_diffs`, `pause_for_decisions`) honored from
   `plan.metadata`; unresolved conflicts now block completion instead of
   reporting success silently.
5. **Batched commits for git_offline** — `GitCommitBatching` policy;
   write p50 dropped ~150ms → ~46ms (3x); outbox replay 55 → 220
   entries/sec. Serialized git operations behind a reentrant lock.
6. **Two-repo sync integration test** — bidirectional convergence through
   a shared bare remote verified (`two_repo_sync_test.dart`).
7. **Chaos tests added** (`outbox_chaos_test.dart`) — corrupted queue
   file, deleted queue file, duplicate delivery: all pass. User data
   survives every scenario.

## Blocking Items

1. **Concurrent `saveFile` race on queue file** — two concurrent kernel
   writes racing on `.us/sync_queue_v1.json`: second call throws
   `FileAlreadyExistsException` despite the catch guard in
   `StorageService.saveFile` (interface, line 40). Isolated repro shows the
   guard works; the chaos test still escapes it. Suspect stale build
   artifact or a second save path. Repro: `race2_test.dart`
   (universal_storage_sync/test). Exit condition: chaos test
   "interleaved writes never lose an entry" passes.

## Non-blocking (step 4 of production plan)

- CHANGELOG entries for interface (SyncAvailability, saveFile race guard),
  sync (kernel split, migration fixes), git_offline (batching), conformance
  (new package).
- Docs: conformance suite usage, capability model, batching policy.
- CI: wire migration benchmarks as regression gates (currently print-only).

## Green Criteria

Release is unblocked when the blocking item above is green AND the full
suite passes across all eight universal_storage packages.
