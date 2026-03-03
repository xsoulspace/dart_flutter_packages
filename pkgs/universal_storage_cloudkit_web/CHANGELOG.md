# Changelog

All notable changes to this project will be documented in this file.

## 0.1.0-dev.1 - 2026-03-03

- Initial web bridge package for CloudKit provider.
- Added generated raw CloudKit global binding and a manual normalized wrapper.
- Added generation script scaffold (`tool/generate.dart`).
- Added generated raw interop snapshot verification test.
- Added native CloudKit JS object-model mode (`configure` + default container +
  private database operations) with adapter-surface fallback.
- Added browser test coverage that stubs global `CloudKit` and validates
  CRUD/query/change-delta flow through `CloudKitWebBridge`.
- Switched `tool/generate.dart` to shared `xsoulspace_js_interop_codegen`
  parsing/emit flow and expanded pinned CloudKit `.d.ts` surface.
- Added generated API snapshot/diff outputs (`tool/api_snapshot.json`,
  `tool/api_diff.json`) for deterministic CI checks.
- Replaced deprecated `dart:js_util` usage with `dart:js_interop` +
  `dart:js_interop_unsafe` in web runtime and browser tests.
