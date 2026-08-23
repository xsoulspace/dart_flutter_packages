# Changelog

## Unreleased (0.1.0-dev.3)

### Breaking changes

- **Hard cut**: GitHub implementation moved out to the new
  `universal_storage_github_oauth` package. This package is now
  contracts-only: `OAuthProvider`, `OAuthFlowDelegate`, models,
  and credential storage.
  - Removed: `GitHubOAuthProvider`, `GitHubRepositoryService`,
    `StoredCredentials.fromOauth2Credentials`, the
    `example/basic_oauth_example.dart` example.
  - Removed dependencies: `github`, `oauth2`, `oauth2_client`, `http`.
  - Migration: depend on `universal_storage_github_oauth` instead; it
    re-exports all contracts and provides a device-flow-first provider.

## 0.1.0-dev.2

- Added package documentation for publication readiness.
