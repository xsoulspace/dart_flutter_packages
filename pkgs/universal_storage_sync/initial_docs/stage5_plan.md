# Universal Storage Sync – Stage-5 Refinement Plan
# =================================================
# FINAL GOAL
# ---------
# Deliver a “Stage-5 Refinement” Pull-Request that upgrades developer-ergonomics
# (typed configs, unified error-handling, provider factory, docs/tests)
# **without** breaking existing public API.

# 1. API Ergonomics Upgrade
# -------------------------
- [ ] 1.1 Introduce builders for all configs  
      • `GitHubApiConfigBuilder`  
      • `OfflineGitConfigBuilder`  
      • `OfflineGitConfigBuilder.authentication()` → supports SSH / token  
      • keep `toMap()` for backward-compat.
- [ ] 1.2 Add `initWithConfig(StorageConfig)` to `StorageProvider`; mark old `init(Map)` as @deprecated.  
- [ ] 1.3 Create `StorageFactory.create(config)` that:
      • figures-out provider type  
      • calls `initWithConfig`  
      • returns ready-to-use `StorageService`.

# 2. Unified Error Handling
# -------------------------
- [ ] 2.1 Ensure every provider throws only subclasses of `StorageException`.  
- [ ] 2.2 Add missing mappings in `filesystem_storage_provider.dart`.  
- [ ] 2.3 Write doc-comments & examples for each exception.

# 3. Cross-Provider Utilities
# ---------------------------
- [ ] 3.1 `RetryableOperation.execute` → wrap GitHub & future providers.  
- [ ] 3.2 `AuthenticatedProvider` mixin → DRY `isAuthenticated` & token checks.  
- [ ] 3.3 `PathNormalizer.normalize(path, ProviderType)`.

# 4. Capability Mix-ins
# ---------------------
- [ ] 4.1 Create `SyncCapable` & `VersionControlCapable` mix-ins.  
- [ ] 4.2 Make `OfflineGitStorageProvider` & future Git provider implement both;  
      GitHub provider only `VersionControlCapable`.

# 5. Provider Selector Helper
# ---------------------------
- [ ] 5.1 `ProviderSelector.recommend({needsVersionControl, needsOffline, hasGitCli, isWeb})`  
      returns ideal config template & provider name.

# 6. Tests & Quality Gates
# ------------------------
- [ ] 6.1 Add unit tests for new builders, factory, selector, retry helper.  
- [ ] 6.2 Refactor existing tests to use typed configs.  
- [ ] 6.3 Enforce `flutter analyze` & `dart test` in CI.

# 7. Documentation & Examples
# ---------------------------
- [ ] 7.1 Update dartdocs for all public APIs.  
- [ ] 7.2 Extend `example/` with:  
      • `config_builder_usage.dart`  
      • `provider_factory_usage.dart`  
- [ ] 7.3 Rewrite README sections: quick-start, provider-comparison table.  
- [ ] 7.4 Add migration guide: Map-based → builder.

# Source Links
# ------------
# • Config classes:  pkgs/universal_storage_sync/lib/src/config/
# • Providers:       pkgs/universal_storage_sync/lib/src/providers/
# • Service & API:   pkgs/universal_storage_sync/lib/src/storage_service.dart
# • Stage-5 doc:     pkgs/universal_storage_sync/stage_5.md