# Changelog

## Unreleased

### Added

- feat: `GitCommitBatching` policy — batched commits make writes ~3x faster
  (write p50 ~150ms → ~46ms); flush points before sync, restore, and
  dispose; see README for tradeoffs.
- feat: reentrant git operation lock serializes all git commands.

### Fixed

- fix: merge pull uses `--allow-unrelated-histories`.
- fix: sync without a configured remote is a graceful no-op instead of
  throwing.
- fix: `listDirectory` returns names relative to the queried directory.
- fix: trailing-slash / leading-slash paths are normalized to the same
  object as their canonical form.

## 0.1.0-dev.3

- Added package documentation for publication readiness.
