# ADR 0006: Universal Storage production hardening — kernel split, conformance suite, capability model, batched commits

- Status: Accepted
- Date: 2026-08-22
- North Star impact: `clarifies`

## Context

Universal Storage spans 16 packages claiming "easy to swap, easy to replicate,
local or remote backend" — but the claim was unverified. Specific gaps:

1. `StorageKernel` (universal_storage_sync) was a 1200-line god class mixing
   read/write routing, outbox replay, conflict staging, migration flows, and
   observability emission. Untestable in isolation.
2. Each backend had bespoke tests only. Nothing enforced that swapping
   filesystem → local_db → git_offline preserved behavior. Two real bugs were
   invisible: trailing-slash paths broke reads in two backends; local_db's
   `sync()` silently no-op'd instead of throwing.
3. Three capability mixins (`RemoteSyncCapable`, `VersionControlCapable`,
   `AuthenticatedProvider`) had zero adopters — dead code competing with the
   real surfaces (`StorageProvider.sync`, `VersionControlService`,
   `StorageCapabilities`). git_offline claimed `supportsSync: true` while
   requiring a remote URL.
4. The migration manager ignored `plan.metadata['overwrite']` — plans behaved
   differently depending on entry point, and an unresolved conflict could be
   reported as `MigrationStatus.completed` (silent data-loss risk).
5. git_offline committed on every write (~150ms p50), making it unusable as a
   sync target for write-heavy workloads.

## Decision

1. **Kernel decomposition** — split into `ObservationHub`, `OutboxManager` +
   `OutboxReplayer`, and `MigrationCoordinator` under `src/kernel/`.
   `StorageKernel` remains a thin facade; public API unchanged.
2. **Conformance suite** — new `universal_storage_conformance` package.
   Backends opt in via `storageProviderConformanceTests(create: ...)`.
   Platform-specific backends run the same suite in their own environment;
   network backends use injected fakes (github_api got a `githubClient`
   injection seam + in-process fake HTTP server; cloudkit already had a fake
   bridge). Optional capabilities are declared per-suite
   (`supportsSync`, `supportsRestore`).
3. **Capability model** — delete dead mixins; add `SyncAvailability`
   tri-state to `StorageCapabilities`: `none` (local-only), `always`
   (CloudKit, github_api), `withRemoteConfig` (git_offline without URL).
   Kernel treats `CapabilityMismatchException` from sync as a graceful no-op
   that retains outbox entries rather than failing the sync loop.
4. **Migration manager** — explicit parameters win; plan metadata is the
   fallback. Unresolved conflicts add issues and block completion.
5. **Batched commits** — `GitCommitBatching(maxDelay, maxPendingOperations)`;
   file mutations write through immediately (reads always consistent), git
   commits coalesce. Flush forced before sync/restore/dispose. All git
   operations serialized behind a reentrant lock.

## Consequences

- Write p50 for git_offline drops ~150ms → ~46ms; outbox replay throughput
  rises ~55 → ~220 entries/sec.
- Backend swaps are now behaviorally verified, not aspirational.
- Breaking changes accepted while pre-stable: mixins deleted, `sync()`
  semantics changed (no-op vs throw), `LocalDbStorageProvider.sync` now
  throws. Must be called out in CHANGELOG before any stable release.
- Known open item: concurrent `saveFile` race on the queue file (see
  `BLOCKERS_NEXT.md`). Guard exists but chaos test still escapes it.

## Alternatives considered

- Keep god class, add tests around it — rejected: test isolation stays
  impossible, every fix risks unrelated breakage.
- Drop git_offline instead of batching — rejected: versioned storage is a
  core differentiator; batching is a contained fix.
- Vector clocks for multi-device conflicts — deferred: current
  last-writer-wins with deterministic ids covers single-user multi-device;
  documented as a limitation.
