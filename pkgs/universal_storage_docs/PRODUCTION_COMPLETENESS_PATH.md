# Universal Storage: Path To Production Completeness

Last updated: `2026-03-03`

This document tracks only remaining work needed to ship Universal Storage as
production-complete across packages and integrated apps.

## 1) Definition Of Production Complete

Universal Storage is production-complete only when all of the following are
true:

1. Contract completeness:
   - Public contracts are stable for one release window.
   - No provider method required by `StorageProvider` /
     `VersionControlService` throws `UnimplementedError` or
     `UnsupportedOperationException` for expected flows.
2. Integration completeness:
   - All target apps build and run with current storage API.
   - Primary app data paths are using storage kernel/profile paths (not only
     bootstrap markers).
3. Reliability completeness:
   - Local durability and startup recovery are validated in failure tests.
   - Sync/migration paths include rollback and decision tracking behavior.
4. Quality completeness:
   - Package-level tests exist for all core packages (including
     `universal_storage_interface` and `universal_storage_db`).
   - Automated release checks include tests + analyze for packages and
     integrated apps.
5. Operational completeness:
   - Migration/sync observability is wired and documented.
   - Release gate checklist is automated and enforced before release tags.

## 2) Verified Gap Snapshot (2026-03-03)

1. Contract design gate (closed for provider onboarding):
   - `VersionControlService` now exposes explicit
     `VersionControlCapabilities` with `supportsCloneToLocal` and runtime
     resolution APIs.
   - `RepositoryManager.cloneRepositoryToLocal(...)` now blocks unsupported
     clone calls through capability-first checks.
   - Provider capability matrix is now documented (including clone semantics
     impact and CloudKit provider behavior).
   - Remaining: migrate any app-level direct clone call sites to the guarded
     flow.
2. API hygiene gap (closed):
   - `universal_storage_sync_utils` no longer imports
     `universal_storage_sync/src/*` internals for YAML profile loading.
3. Dependency-source drift gap (still open):
   - `daily_budget_planner/packages/mobile_app` already uses
     `pubspec_overrides.yaml`.
   - Other target apps still rely on inline `dependency_overrides` in
     `pubspec.yaml` for Universal Storage paths.
4. Data-path migration gap (partially closed):
   - `prompt_character` workspace/prompt runtime writes now persist in kernel
     `workspace`/`prompts` namespaces, and workspace/prompt reads are now
     kernel-first with compatibility fallback to legacy workspace files and
     migration test coverage.
   - `drip` sync queue now persists in kernel `queue` namespace with
     compatibility fallback to legacy `LocalDbI` keys, and remote data setting
     now persists in kernel `settings` namespace with legacy fallback and
     migration test coverage.
   - `word_by_word_game` game saves now persist in kernel `saves` namespace
     with compatibility fallback to legacy `LocalDbI` key `game_save`, and app
     settings now persist in kernel `settings` namespace with legacy fallback
     and migration test coverage.
   - `daily_budget_planner` monthly/weekly budgets now persist in kernel
     `budget` namespace, and user/settings now persist in kernel `user` /
     `settings` namespaces, all with compatibility fallback to legacy
     `LocalDbI` keys and migration test coverage.
   - `last_answer/packages/core` projects now persist in kernel `projects`
     namespace, and tags now persist in kernel `tags` namespace, both with
     compatibility fallback to legacy Isar/local/SharedPreferences data
     sources and migration test coverage.
   - Remaining: remove compatibility bridges after bake-in windows.
5. Coverage and reliability gaps (still open):
   - `universal_storage_interface` has no dedicated `test/` suite.
   - `universal_storage_db` has no dedicated `test/` suite.
   - Failure-mode suites are incomplete for crash/replay/rollback under stress.
6. Release gate integration gap (still open):
   - `StorageReleaseGateEvaluator` (Gate G6) exists with tests in
     `universal_storage_sync`, but is not wired as a hard automated release
     gate.

## 3) Current Integration Coverage (As-Is)

### 3.1 Target App Coverage Matrix

| Target app | Kernel bootstrap | App-level storage smoke test |
| --- | --- | --- |
| `prompt_character` | yes (`PromptCharacterStorageKernelBootstrap`) | yes (`test/storage_kernel_bootstrap_test.dart`) |
| `drip` | yes (`DripStorageKernelBootstrap`) | yes (`test/storage_kernel_bootstrap_test.dart`) |
| `word_by_word_game` | yes (`WordByWordStorageKernelBootstrap`) | yes (`test/game/storage/storage_kernel_bootstrap_test.dart`) |
| `daily_budget_planner/packages/mobile_app` | yes (`DailyBudgetStorageKernelBootstrap`) | yes (`test/storage_kernel_bootstrap_test.dart`) |
| `last_answer/packages/core` | yes (`LastAnswerStorageKernelBootstrap`) | yes (`test/state_di/storage_kernel_bootstrap_test.dart`) |

### 3.2 Primary Legacy Data Sources By App

1. `prompt_character`
   - Workspace/prompt write + read migration slices are landed:
     - kernel-backed writes in `workspace` and `prompts` namespaces,
     - kernel-first reads for `workspace.yaml` and prompt content,
     - kernel prompt-path listing to include kernel-only prompts in indexing,
     - compatibility mirror to legacy workspace filesystem paths,
     - migration + rollback recipe and verification tests.
   - Remaining: remove compatibility mirror/fallback bridge after bake-in.
2. `drip`
   - Sync queue + remote-data-settings migration slices are landed:
     - kernel-backed queue state in `queue` namespace,
     - kernel-backed remote data toggle in `settings` namespace,
     - compatibility fallback to legacy `LocalDbI` keys,
     - migration + rollback recipe and verification tests.
   - Remaining: remove fallback bridges after bake-in window.
3. `word_by_word_game`
   - Game saves + app settings migration slices are landed:
     - kernel-backed save state in `saves` namespace,
     - kernel-backed app settings state in `settings` namespace,
     - compatibility fallback to legacy `LocalDbI` key `game_save`,
     - migration + rollback recipe and verification tests.
   - Remaining: remove fallback bridges after bake-in window.
4. `daily_budget_planner/packages/mobile_app`
   - Budget + user/settings migration slices are landed:
     - kernel-backed monthly/weekly budget state in `budget` namespace,
     - kernel-backed user state in `user` namespace,
     - kernel-backed app settings state in `settings` namespace,
     - compatibility fallback to legacy `LocalDbI` keys (`monthly_budget` /
       `weekly_budget` / `user` / `settings`),
     - migration + rollback recipe and verification tests.
   - Remaining: remove fallback bridges after bake-in window.
5. `last_answer/packages/core`
   - Projects + tags migration slices are landed:
     - kernel-backed project state in `projects` namespace,
     - kernel-backed tags state in `tags` namespace,
     - compatibility fallback to legacy Isar/local DB / SharedPreferences
       data sources,
     - migration + rollback recipe and verification tests.
   - Remaining: remove fallback bridges after bake-in window.

## 4) Active Execution Plan (Remaining Work Only)

## R1. Finalize Capability Contracts

Goal: remove runtime-only VC capability ambiguity.

Status (2026-03-03): provider gate complete for new-provider onboarding.

Required work:

- Add explicit VC capability declaration for clone semantics (for example,
  `supportsCloneToLocal`) in public contracts.
- Enforce capability checks before clone invocation in shared orchestration
  paths (including repository workflow helpers).
- Replace runtime clone attempts with guard-driven behavior and actionable
  fallback messaging.
- Add provider tests proving:
  - API-only provider clone is blocked at contract/capability layer.
  - local-git provider clone flow is either implemented or contractually
    excluded from expected execution paths.

Exit criteria:

- No production path reaches unsupported clone by surprise.
- VC capability matrix is explicit in docs and asserted in tests.

## R2. Normalize Dependency Source Resolution

Goal: remove cross-workspace dependency drift for Universal Storage packages.

Required work:

- Standardize Universal Storage path sourcing via `pubspec_overrides.yaml`
  across all target apps.
- Remove remaining inline `dependency_overrides` for Universal Storage paths
  from target app `pubspec.yaml` files.
- Add a lightweight workspace audit command/report that flags path-source drift
  before release tagging.

Exit criteria:

- Dependency source resolution is consistent across target apps.
- Release checklist fails when path-source drift is reintroduced.

## R3. Bake-In And Bridge Removal (M3)

Goal: retire temporary compatibility bridges after safe bake-in windows.

Required work:

1. Define bake-in windows and rollback thresholds for each migrated app slice:
   - `prompt_character`: workspace + prompts;
   - `drip`: queue + remote-data settings;
   - `word_by_word_game`: saves + app settings;
   - `daily_budget_planner`: budget + user/settings;
   - `last_answer`: projects + tags.
2. Add fallback-path usage observability per migrated domain (read fallback,
   write fallback, legacy mirror writes).
3. Remove compatibility bridges and legacy mirror writes where fallback usage
   remains zero for a full bake-in window.
4. Remove obsolete legacy-key cleanup and migration backfill branches once
   bridge removal is complete.
5. Keep migration docs updated with final cutover date and rollback owner.

Exit criteria:

- No primary read/write path depends on legacy stores.
- Compatibility bridge code is removed for all migrated domains.
- Rollback playbook is explicit and time-bounded per domain.

## R4. Hardening, Coverage, And Release Gate (M4)

Goal: lock quality and release safety before tag.

Required work:

- Add dedicated package tests for:
  - `universal_storage_interface`
  - `universal_storage_db`
- Expand failure-mode coverage for:
  - crash during write + startup recovery
  - replay/idempotency recovery
  - conflict decision workflows
  - migration rollback under stress
- Wire Gate G6 (`StorageReleaseGateEvaluator`) into release workflow as
  blocking stage with explicit artifacts (JSON report + failing conditions).
- Define and enforce baseline SLO budgets in gate input payloads:
  - startup recovery p95 bound
  - sync queue throughput floor
  - migration/outbox stress coverage minimums

Exit criteria:

- Gate G6 is mandatory and green for package + app matrix.
- Release candidate tag is blocked until R1-R4 are all green.

## 5) Immediate Next Order (Execution Queue)

1. R1: capability-first clone contract and provider guarding.
2. R2: normalize `pubspec_overrides.yaml` adoption across all target apps.
3. R3: define bake-in windows and remove compatibility bridges per app.
4. R4: interface/db tests and blocking Gate G6 release integration.

## 6) Working Session Checklist (Next 2 Iterations)

1. Iteration A (dependency + bake-in baseline)
   - Normalize `pubspec_overrides.yaml` usage in all target apps.
   - Define bake-in windows and fallback-usage thresholds for each migrated
     domain.
   - Capture baseline fallback-path metrics for all app slices.
2. Iteration B (contract + migration kickoff)
   - Land VC capability contract update and provider test coverage.
   - Plan compatibility bridge removals after completed second slices in
     `prompt_character`, `drip`, `word_by_word_game`,
     `daily_budget_planner`, and `last_answer`.
   - Start Gate G6 release-workflow wiring with placeholder evidence artifact
     generation.

## 7) Governance Rules Until Production

1. New providers require a green R1 capability-contract gate (now satisfied;
   keep enforced for subsequent providers).
2. No app is marked migrated while primary flow still uses old storage path as
   source-of-truth.
3. Every storage/sync/migration behavior change must ship with:
   - tests
   - docs update
   - release gate update (if applicable)
