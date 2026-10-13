# Tooling runtime

Reusable IO mechanics under harness ADR 0091 and DFP ADR 0066. North Star
impact: applies. No ECS, Flutter, inference provider, consent authority,
world scheduler, file-content writer or transaction owner. WorkspacePathPolicy
retains root-directory creation and mutable policy resolution; FileLockTable
retains cooperative reentrant leases. Neither is an OS isolation boundary.

POSIX runs use an automatically selected trusted system Perl helper to establish
an acknowledged private session, preserve argv/stdio and observe target exec.
Missing session helper or process observation refuses explicitly. This is group
lifecycle ownership, not OS filesystem/network isolation; children creating new
groups/sessions remain outside the qualified boundary. Unsettled pipes or
observation failures never certify physical settlement.

Gate from DFP root: `just check xsoulspace_tooling_runtime`. The lock-free Dart
lane with FLUTTER_ROOT is supported for process tests. Keep original RED and
matched SDK controls; no live-process restart merely because observation waits.


Candidate verification is explicitly `macos_no_fork_candidate_v1`: deny-default
native profile, no Mach/AppleEvents/network/fork, and session-leader exec. Keep
SDK/cache roots host-built; no model profile or uncontained fallback. Check
`physicallySettled` before outer candidate cleanup and retain false/quarantined
obligations. Bounded input must reach EOF or report failure under the same
process deadline. Generic fork-capable jobs, unsupported Darwin NOTE_TRACK and
deprecated sandbox-exec release replacement remain open; never relabel the
no-fork Dart lane as their completion. See ADR 0066.
