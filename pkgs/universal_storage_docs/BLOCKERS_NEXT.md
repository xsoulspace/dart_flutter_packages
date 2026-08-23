# Universal Storage: Next Blockers

Last updated: `2026-08-23`

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
8. **Concurrent `saveFile` race on queue file FIXED** — root cause was
   twofold: (a) in async Dart, a bare `return future` inside `try`
   bypasses the surrounding catch clauses, so the
   `on FileAlreadyExistsException → updateFile` guard in
   `StorageService.saveFile` never engaged (fix: `return await`,
   interface package); (b) even with the guard,
   `OutboxManager.enqueue`'s load→save cycle lost entries under
   concurrency — fixed by a serialized `SyncQueueStore.mutateState`
   read-modify-write primitive (`package:synchronized`).
   Evidence: chaos suite 4/4 green; full sync suite (75 tests incl.
   scenarios + benchmarks + chaos) green; race repro tests deleted.
9. **Step-4 release items** — CHANGELOGs for all universal_storage
   packages (breaking mixin removals and sync-semantics changes flagged);
   conformance README (adoption guide + capability model table:
   backend × SyncAvailability × restore); git_offline README section on
   `GitCommitBatching` usage and tradeoffs; migration/write benchmarks
   wired as soft CI gates (filesystem migration ≥50 files/sec, batched
   git write p50 <100ms).

## Blocking Items

None.

## Non-blocking (step 4 of production plan)

None remaining from this cycle.

## Green Criteria

Release is unblocked when the blocking item above is green AND the full
suite passes across all eight universal_storage packages.
