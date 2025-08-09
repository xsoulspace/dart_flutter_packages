## Universal Storage – Migration Implementation Plan

Context

- Goal: Finish migration to `universal_storage_interface`, standardize providers, and land a stable, testable API similar to `xsoulspace_monetization_foundation` pattern.
- Workspace: `xsoulspace_packages` (branch: fix/monetization)
- Packages in scope:
  - `pkgs/universal_storage_interface` (new, contracts/models)
  - `pkgs/universal_storage_sync` (providers/factory/service)
  - `pkgs/universal_storage_sync_utils` (utility consumers; follow-up alignment)
  - Planned provider packages (split by concrete backend, see Phase 2 below):
    - `pkgs/universal_storage_filesystem` (FileSystem provider)
    - `pkgs/universal_storage_github_api` (GitHub API provider)
    - `pkgs/universal_storage_git_offline` (Offline Git provider)

What’s already done

- Created `universal_storage_interface` with:
  - Exceptions, `StorageProvider`/`StorageConfig` contracts, `FileEntry`, `FileOperationResult` models
  - VC models (`VcRepository`, `VcBranch`, `VcUrl`, `VcRepositoryName`, etc.)
  - `ConflictResolutionStrategy`
- `universal_storage_sync` now depends on the interface.
- Refactors completed:
  - `StorageService` uses unified return types: `FileOperationResult`, `List<FileEntry>`
  - `FileSystemStorageProvider` updated to unified types and consistent list behavior
  - `OfflineGitStorageProvider` updated to unified types and consistent list behavior
  - `GitHubApiStorageProvider` partially updated to typed models and unified types
  - Removed local `src/storage_provider.dart` to avoid name conflicts
  - `StorageFactory` updated to import from the interface
  - `universal_storage_sync.dart` exports the interface first

Open items / known gaps

- GitHub provider
  - Replace remaining map-based `VcRepository`/`VcBranch` object creation with typed constructors (partially done)
  - Remove redundant null-coalescing on non-null fields (warnings show lines where `??` is unnecessary)
  - Remove `delResult` unused variable in delete operation
- Offline Git provider
  - Stop referencing `.empty` constructor; replaced with default constructor (done); verify no lingering usages
  - Use typed `VcRepository` constructor in `createRepository` (done); verify compile
  - Ensure no uses of `_branchName!.value` (should be `_branchName.value`)
  - Currently `_conflictResolution` is hardcoded to `clientAlwaysRight`. Consider reading from config once available or keep default with a TODO
- Providers parity
  - Ensure `listDirectory` always returns `List<FileEntry>` and missing directories yield `[]` where intended (Filesystem: returns []; Offline Git: throws; GitHub: returns []; verify desired policy per provider)
- Import hygiene
  - Ensure all providers/services import exceptions and models from `universal_storage_interface`
  - Confirm no residual imports from removed local files
- Utils
  - Review `universal_storage_sync_utils` for any model/exception imports that should target `universal_storage_interface` later (non-blocking for this PR)
- Tests & docs
  - Update unit tests to new return types and behaviors (create/update/delete results, directory listings)
  - Document breaking changes and add short migration notes in README(s)

Acceptance criteria

- Build passes and analyzer is clean (no errors; warnings minimized) in:
  - `pkgs/universal_storage_interface`
  - `pkgs/universal_storage_sync`
- All providers compile and conform to `StorageProvider` interface
- Unified behaviors:
  - `createFile` throws `FileAlreadyExistsException` if file exists
  - `updateFile` throws `FileNotFoundException` if target missing
  - `deleteFile` throws `FileNotFoundException` if target missing
  - `listDirectory` returns `List<FileEntry>`; consistent policy per provider (documented in code)
- VC models usage is typed (no map-based construction)
- `StorageFactory.create` selects correct provider variant and returns an initialized `StorageService`
- README reflects updated usage, and a brief migration section exists

Step-by-step tasks

1. Finish GitHub provider typed conversions

   - Replace all `VcRepository({...})` usages with:
     - `VcRepository(id: ..., name: ..., description: ..., cloneUrl: ..., defaultBranch: ..., isPrivate: ..., owner: ..., fullName: ..., webUrl: ...)`
   - Replace all `VcBranch({...})` usages with:
     - `VcBranch(name: VcBranchName(...), commitSha: ..., isDefault: ..., isProtected: false)`
   - Remove unnecessary `??` from non-null SDK fields where analyzer warns
   - Remove the unused `delResult` variable in delete operation

2. Verify Offline Git provider

   - Ensure config default creation uses `OfflineGitConfig()`
   - Confirm all occurrences of `_branchName!.value` are changed to `_branchName.value`
   - Confirm `createRepository` uses the typed `VcRepository` constructor (no maps)
   - Decide policy for `_conflictResolution` (keep default, or wire to config when available)

3. Normalize listDirectory behavior

   - Filesystem: return `[]` on missing dir (already done)
   - GitHub: return `[]` on 404 (already done)
   - Offline Git: choose consistent behavior: either return `[]` or throw – update tests and docs accordingly (currently throws `FileNotFoundException`)

4. Import hygiene

   - Ensure all storage providers only import from `package:universal_storage_interface/universal_storage_interface.dart`
   - Verify `universal_storage_sync.dart` exports are ordered to expose interface first and local API second

5. Tests & docs

   - Update unit tests under `pkgs/universal_storage_sync/test` to new return types and exception behavior
   - Add short migration notes in `pkgs/universal_storage_sync/README.md` (what changed and why)

6. Run and fix

   - In both packages:
     ```bash
     dart pub get
     dart analyze
     dart test
     ```
   - Resolve any analyzer errors/warnings introduced by the refactor

7. (Optional, next iteration)
   - Introduce `universal_storage_foundation` for shared retry/backoff and orchestration
   - Implement missing `VersionControlService` methods (clone, set repo) robustly with retries and better error mapping
   - Move cross-platform picker/bookmark models to interface if needed by consumers

File-by-file checklist

- `pkgs/universal_storage_sync/lib/src/providers/github_api_storage_provider.dart`
  - [ ] Replace all map-based VC model creations with typed constructors
  - [ ] Remove redundant `??` on non-null left operands
  - [ ] Remove unused `delResult` variable in delete method
- `pkgs/universal_storage_sync/lib/src/providers/offline_git_storage_provider.dart`
  - [ ] Ensure default config construction (no `.empty`)
  - [ ] No `!` on `_branchName` accessors
  - [ ] Typed `VcRepository` constructor usage
  - [ ] Decide/annotate `listDirectory` behavior and keep consistent
- `pkgs/universal_storage_sync/lib/src/storage_factory.dart`
  - [ ] Imports only from interface/local providers
  - [ ] Provider selection uses new config types
- `pkgs/universal_storage_sync/lib/src/storage_service.dart`
  - [ ] All signatures use unified result types
- `pkgs/universal_storage_interface/*`
  - [ ] Exports include `conflict_resolution_strategy.dart`
  - [ ] No analyzer issues

Command cheat sheet

```bash
# From repo root
cd pkgs/universal_storage_interface && dart pub get && dart analyze && cd -
cd pkgs/universal_storage_sync && dart pub get && dart analyze && dart test
```

Notes / design decisions

- Keeping `OfflineGit` conflict resolution as `clientAlwaysRight` by default until config is formalized
- Directory listing policy: Filesystem/GitHub return `[]` when missing; Offline Git throws – reevaluate and harmonize if desired

Done criteria

- Analyzer clean, tests updated, providers compiled, typed models everywhere (no map-based init), README migration notes added.

---

## Phase 2 – Split providers into separate packages (align with architecture.md)

Objective

- Adopt the Interface → Providers → Foundation structure (as in monetization architecture) to improve modularity, testability, and independent release cadence per provider.

Target package topology

- Interfaces

  - `pkgs/universal_storage_interface` (already done)

- Providers (new)

  - `pkgs/universal_storage_filesystem`
    - Depends on: `universal_storage_interface`
    - Exposes: `FileSystemStorageProvider`
  - `pkgs/universal_storage_github_api`
    - Depends on: `universal_storage_interface`, `github`, `retry`
    - Exposes: `GitHubApiStorageProvider`
  - `pkgs/universal_storage_git_offline`
    - Depends on: `universal_storage_interface`, `git`, `path`, `retry`
    - Exposes: `OfflineGitStorageProvider`

- Foundation
  - `pkgs/universal_storage_sync` (current)
    - Depends on: `universal_storage_interface`, the three provider packages above
    - Exposes: `StorageService`, `StorageFactory`, provider selector/tutorials

Deliverables

- Provider code moved out of `universal_storage_sync/lib/src/providers/` into their respective packages with unchanged public class names.
- `StorageFactory` imports updated to use provider packages.
- Provider-specific unit tests live with their respective provider packages; keep integration/service tests in `universal_storage_sync`.
- README migration notes and examples updated for new import paths.

Step-by-step

1. Create provider package skeletons

- For each package (`filesystem`, `github_api`, `git_offline`):
  - `pubspec.yaml`: name, description, version, environment, dependencies (see above)
  - `analysis_options.yaml`: include org lints
  - `lib/<package_name>.dart`: export the provider class and any internal src files
  - `lib/src/...`: move provider implementation files
  - `test/`: move provider-specific tests
  - `README.md`: brief usage and dependency notes

2. Move code

- Move files from `universal_storage_sync/lib/src/providers/*.dart` into corresponding provider packages under `lib/src/`.
- Adjust imports to `package:universal_storage_interface/universal_storage_interface.dart` exclusively.

3. Update foundation (`universal_storage_sync`)

- Remove moved provider files from `src/providers/`.
- Add dependencies on the three provider packages in `pubspec.yaml`.
- Update `src/storage_factory.dart` to import providers from their packages and keep the same selection logic by `StorageConfig` type.
- Ensure `universal_storage_sync.dart` continues to export the interface first, then foundation API (do not re-export provider packages).

4. Tests & examples

- Move provider-specific tests into provider packages; leave `StorageService` integration tests here.
- Update example imports:
  - Direct provider usage examples should import provider packages directly.
  - Service-based examples remain unchanged, as `StorageFactory` delegates to providers.

5. CI and quality gates

- Add analyze/test jobs for each new package.
- Ensure all packages build and analyze cleanly.

6. Migration notes

- Breaking import changes for direct provider usage:
  - `FileSystemStorageProvider`: `package:universal_storage_filesystem/universal_storage_filesystem.dart`
  - `GitHubApiStorageProvider`: `package:universal_storage_github_api/universal_storage_github_api.dart`
  - `OfflineGitStorageProvider`: `package:universal_storage_git_offline/universal_storage_git_offline.dart`
- `StorageService` and `StorageFactory` continue to be imported from `package:universal_storage_sync/universal_storage_sync.dart`.

Acceptance for Phase 2

- New provider packages compile, analyze clean, and pass their unit tests.
- `universal_storage_sync` depends on provider packages and passes all integration tests.
- Examples and README updated to reflect new import paths.
