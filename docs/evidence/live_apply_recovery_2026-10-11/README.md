# Live-apply recovery qualification — 2026-10-11

Owning package: `universal_storage_live_apply`. Contract: [ADR 0062](../../decisions/0062_live_apply_write_ahead_recovery.md).

## Prediction versus observation

The first added regression run against the original implementation failed all
five controls below. After repair they pass; the owning full gate passes all
38 tests. Baseline parent is `fc7422bf`; a concurrent actor captured most repairs
in `60d7298e`, before the final lint/Flutter worker corrections. Source identity
for the final gate includes that revision plus declared working-tree overlays.

| Control | Original observed failure | Repair |
| --- | --- | --- |
| Empty post-content restores prior | Drift refusal despite present empty file | Explicit presence separate from content hash |
| Empty post-content removed externally | Inverse overwrote unexplained absence | Presence participates in drift checks |
| Effect before completion journaling | Reopened inverse refused its own candidate | Durable pre/intended states before provider dispatch |
| Provider exception after effect | Wrapper deleted the only recovery journal | Prune only after locked unchanged-footprint read-back |
| Interruption after inverse effect | Reopened inverse treated restored file as drift | Durable rollingBack and per-path inverse progress |

Additional controls cover faults in journal intent/completion publication,
inverse completion publication, unknown versions/statuses, legacy ambiguity,
UTF-8 snapshot limits, stale handles, failed deletion, settlement drift and
cooperating writer exclusion. Actual macOS processes are killed with SIGKILL
after forward and inverse effects; a separate process holds the store lock.
All children are joined before test completion.

## Validation

- `dart analyze lib test`: no issues.
- `just check universal_storage_live_apply`: exit 0; analyzer clean and 38/38
  Flutter tests pass. [Final transcript](package-gate.log).
- [Before](source-before.json) / [after](source-after.json) content identities
  include package tests plus live-apply/interface/filesystem library sources.
  All captured files remain unchanged across the final gate.
- `git diff --check`: passed.

The initial full Flutter gate failed three worker launches because
`Platform.resolvedExecutable` was `flutter_tester`. This is a test-launch defect,
not a recovery success. [Retained red](package-gate-flutter-runner-red.log).
The test now resolves the Dart VM from that same SDK, and the actual process
controls pass under both Dart and Flutter runners.

## Coordination and limits

The shared harness orientation was unavailable. Native work boundaries were
recorded in the harness qualification record. The parallel ZCode storage session
explicitly acknowledged live-apply/ADR 0062 as a separate lane and reserved
ADR 0063/session/mesh files. Preserve its work. No claim of world-level locking
or canonical acceptance follows from this local package gate.

The store lock excludes cooperating callers using the same local journal root.
Hosts still exclude bypass writers; no provider CAS, multi-isolate certification,
distributed rollback, power-loss durability or atomic reader visibility is proven.
Ambiguous old journals remain intact and refuse. `recordPost` now refuses unsafe
post-only effects; direct clients migrate to `mutate`. The meaning package,
harness integration and physical gesture journey have not been implemented here.
