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
   - CI gating includes tests + analyze for packages and integrated apps.
5. Operational completeness:
   - Migration/sync observability is wired and documented.
   - Release gate checklist is automated and enforced before release tags.

## 2) Verified Gap Snapshot (2026-03-03)

1. Contract design gap (still open):
   - `VersionControlService.cloneRepository` is mandatory, but current providers
     still expose runtime-only unsupported paths.
   - `GitHubApiStorageProvider.cloneRepository` throws
     `UnsupportedOperationException`.
   - `OfflineGitStorageProvider.cloneRepository` throws
     `UnsupportedOperationException`.
2. API hygiene gap (still open):
   - `universal_storage_sync_utils` imports internal API from
     `package:universal_storage_sync/src/storage_profile_loader.dart`
     (`YamlStorageProfileLoader`).
3. CI/integration verification gap (still open):
   - No package workspace CI matrix currently enforces Universal Storage
     analyze/test checks.
   - App workflows are missing or release-only and do not enforce storage smoke
     checks.
4. Dependency-source drift gap (still open):
   - `daily_budget_planner/packages/mobile_app` already uses
     `pubspec_overrides.yaml`.
   - Other target apps still rely on inline `dependency_overrides` in
     `pubspec.yaml` for Universal Storage paths.
5. Data-path migration gap (still open):
   - Kernel bootstrap is present in all target apps, but primary domain data
     still persists through legacy local data sources.
6. Coverage and reliability gaps (still open):
   - `universal_storage_interface` has no dedicated `test/` suite.
   - `universal_storage_db` has no dedicated `test/` suite.
   - Failure-mode suites are incomplete for crash/replay/rollback under stress.
7. Release gate integration gap (still open):
   - `StorageReleaseGateEvaluator` (Gate G6) exists with tests in
     `universal_storage_sync`, but is not wired as a hard CI gate.

## 3) Current Integration Coverage (As-Is)

### 3.1 Target App Coverage Matrix

| Target app | Kernel bootstrap | App-level storage smoke test | CI enforcement |
| --- | --- | --- | --- |
| `prompt_character` | yes (`PromptCharacterStorageKernelBootstrap`) | no dedicated bootstrap smoke test | none |
| `drip` | yes (`DripStorageKernelBootstrap`) | yes (`test/storage_kernel_bootstrap_test.dart`) | not enforced |
| `word_by_word_game` | yes (`WordByWordStorageKernelBootstrap`) | yes (`test/game/storage/storage_kernel_bootstrap_test.dart`) | not enforced |
| `daily_budget_planner/packages/mobile_app` | yes (`DailyBudgetStorageKernelBootstrap`) | no dedicated bootstrap smoke test | not enforced |
| `last_answer/packages/core` | yes (`LastAnswerStorageKernelBootstrap`) | yes (`test/state_di/storage_kernel_bootstrap_test.dart`) | not enforced |

### 3.2 Primary Legacy Data Sources By App

1. `prompt_character`
   - Workspace and prompt flows are still direct file-service based
     (`workspace.yaml`, prompt files), not kernel-first for production reads.
2. `drip`
   - Sync queue is stored in legacy `LocalDbI` key-value entries in
     `lib/services/sync_service.dart`.
3. `word_by_word_game`
   - Game/app settings repositories are `LocalDbI`/`PrefsDb` based
     (`packages/wbw_core`), while kernel namespaces are bootstrap-only.
4. `daily_budget_planner/packages/mobile_app`
   - `BudgetLocalApi`, `UserLocalApi`, and `AppSettingsLocalApi` persist via
     legacy `LocalDbI`.
5. `last_answer/packages/core`
   - Projects/tags use existing Isar/local DB data sources
     (`ProjectsLocalDataSourceIsarImpl` and local storage paths).

## 4) Active Execution Plan (Remaining Work Only)

## R1. Finalize Capability Contracts

Goal: remove runtime-only VC capability ambiguity.

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

## R2. Enforce Integration In CI

Goal: make integration regressions continuously fail-fast.

Required work:

- Add mandatory storage CI jobs for target apps:
  - `prompt_character`
  - `drip`
  - `word_by_word_game`
  - `daily_budget_planner/packages/mobile_app`
  - `last_answer/packages/core`
- Minimum per-app checks:
  - `flutter pub get`
  - targeted `flutter analyze` for bootstrap/DI/storage modules
  - app-level storage smoke test execution
- Add missing bootstrap smoke tests before enforcing matrix:
  - `prompt_character`
  - `daily_budget_planner/packages/mobile_app`
- Standardize Universal Storage path sourcing via `pubspec_overrides.yaml`
  across all target apps (remove drift between inline `dependency_overrides`
  and generated override files).

Exit criteria:

- CI fails on storage integration regressions across app matrix.
- Dependency source resolution is consistent across local/CI runs.

## R3. Migrate Real Data Paths (M3)

Goal: move from bootstrap markers to production data usage.

Required work:

1. `prompt_character`
   - First migration slice: route prompt/workspace runtime writes through
     kernel namespaces (`workspace`, `prompts`) instead of direct ad-hoc paths.
2. `drip`
   - First migration slice: move sync queue persistence from `LocalDbI` keys to
     kernel `queue` namespace.
3. `word_by_word_game`
   - First migration slice: migrate game save persistence to kernel `saves`
     namespace (then settings).
4. `daily_budget_planner/packages/mobile_app`
   - First migration slice: migrate monthly/weekly budget persistence from
     `BudgetLocalApi` local DB keys to kernel `budget` namespace.
5. `last_answer/packages/core`
   - First migration slice: migrate project read/write path from Isar-first to
     kernel `projects` namespace (with compatibility bridge).

For each migration slice above, add:

- one migration recipe (source -> target)
- one rollback recipe
- one migration verification test

Exit criteria:

- Each target app has one documented migrated production domain plus rollback
  test coverage.
- Migrated domain no longer has dual source-of-truth ambiguity.

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
- Wire Gate G6 (`StorageReleaseGateEvaluator`) into CI as blocking stage with
  explicit artifacts (JSON report + failing conditions).
- Define and enforce baseline SLO budgets in gate input payloads:
  - startup recovery p95 bound
  - sync queue throughput floor
  - migration/outbox stress coverage minimums

Exit criteria:

- Gate G6 is mandatory and green for package + app matrix.
- Release candidate tag is blocked until R1-R4 are all green.

## 5) Immediate Next Order (Execution Queue)

1. R2: add missing smoke tests (`prompt_character`, `daily_budget mobile_app`)
   and wire app CI matrix.
2. R1: capability-first clone contract and provider guarding.
3. R3: first production-domain migration in each target app.
4. R4: interface/db tests and blocking Gate G6 integration.

## 6) Working Session Checklist (Next 2 Iterations)

1. Iteration A (CI baseline)
   - Add missing smoke tests for `prompt_character` and daily budget mobile app.
   - Create/extend app workflows to run analyze + storage smoke tests.
   - Normalize `pubspec_overrides.yaml` usage in all target apps.
2. Iteration B (contract + migration kickoff)
   - Land VC capability contract update and provider test coverage.
   - Ship first migrated domain for `drip` (queue) and
     `word_by_word_game` (saves).
   - Start Gate G6 CI wiring with placeholder evidence artifact generation.

## 7) Governance Rules Until Production

1. No new provider is added until R1 capability-contract work is complete.
2. No app is marked migrated while primary flow still uses old storage path as
   source-of-truth.
3. Every storage/sync/migration behavior change must ship with:
   - tests
   - docs update
   - release gate update (if applicable)
