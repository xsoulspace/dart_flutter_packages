# Permission-aware file recovery: measured implementation cut

Direction: [ADR 0068](../../decisions/0068_file_state_live_apply_recovery.md).
The existing DFP journal and filesystem writer now preserve the declared
POSIX text-file state. This is implementation/recovery evidence, not real
model coding, external handoff, product adoption or release acceptance.

## Measured results

| Gate | Result |
| --- | --- |
| Interface tests | 9 passed; changed-source analysis clean |
| Live-apply complete suite | 69 passed; changed transaction/tests analysis clean |
| Filesystem complete native suite | 61 passed; changed source/tests analysis clean |
| Host complete suite | 1,080 passed, 3 skipped; package analysis clean |
| Workspace complete suite | 320 passed, 1 skipped; one export-ordering info then fixed; package analysis clean after fix |

Actual macOS arm64 tests restore 0600, 0644 and 0755 after update/deletion,
including a fresh owner. Mode-only foreign drift refuses the complete inverse
before any restoration. Missing/wrong adapters and native legacy journals
without historical modes refuse without rewriting their evidence.

Five live-apply SIGKILL controls cover forward write, forward deletion,
inverse write, inverse deletion and retained writer exclusion. Fresh recovery
processes run under a different umask and still restore recorded private 0600.
Six additional filesystem SIGKILL controls stop the actual producer at private
staging, prepared-before-publication and published-before-commit boundaries,
for private 0600 and intended 0644 states. Before preparation the target remains
unchanged and the restricted orphan stage is retained; prepared/published
recovery verifies and restores the exact compound state.

Native adoption binds dependency modes into issued source views and stale
checks, uses the same DFP writer, acquires fresh metadata/checks/consent for
saved byte candidates, audits continuation without initializing or replaying
the provider, and denies actor access to `.us` and aliases. Both semantic and
conventional callers pass the current native workspace into continuation.

## Retained evidence and limits

[Source cut](source-cut.json) records thirteen selected implementation inputs;
it is not a complete compiler-input or release manifest. Native process receipts,
logs and full filesystem source fences are retained beside it. Earlier 0600→0644
failures, the interim guards and previous full-suite cuts remain in the harness
implementation ledger. An intermediate shell-test interpolation error was fixed
before the SIGKILL/umask controls passed; no acceptance criterion was weakened.

The interface combined gate still reports 352 existing analyzer infos; the
filesystem full analysis has five existing test infos. No unrelated lint sweep
was performed. Linux, Windows and web execution, ACL/ownership/timestamp/inode
restoration, directory/binary inverses and hardware power-loss durability are
unqualified. Unsupported native kinds/modes refuse. Orphan staging before a
prepared record is retained safely, not attributed or deleted speculatively.

The frozen coding trial failed and remains failed. Its next prospective observer
needs native custody and v3 lineage qualification; the older source-only scope
and schema2 assumptions cannot be silently reused.
