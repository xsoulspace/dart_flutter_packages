# No-fork candidate qualification — 2026-10-13

Native owning gate: `just check xsoulspace_tooling_runtime`, exit zero, analyzer
clean and all 27 tests passed. Source/test/package hashes are in `inputs.sha256`;
`owning-gate-green.log` retains the analyzer and test stages. Earlier native gate
RED in `owning-gate-sdk-root-red.log` records the compiler fixture deriving an
engine directory from Flutter's `flutter_tester` executable. The fixture now
selects the actual Flutter Dart SDK; the functional stdin/output oracle was not
changed to compilation-only acceptance.

Fourteen original process controls remain unchanged. Three lock/path controls,
six candidate containment controls, and four input controls complete this run.

The historical fork-capable profile was independently reproduced as unsafe for
physical settlement: target/root exit 0, child 87747 forked, established another
session, closed stdio and stayed alive. It was explicitly killed and a fresh ps
observation confirmed it gone. No user file, credential, network service or app
was changed. A proposed Darwin NOTE_TRACK tracker was rejected and removed:
installed SDK sys/event.h says NOTE_TRACK/NOTE_CHILD unsupported since 10.5.

Canonical and `/System/Volumes/Data` aliases to a synthetic secret both refused
on this OS even before reducing the `/System` content grant. Alias exposure was
a investigated risk, not a reproduced read leak. The current strict profile uses
`/System/Library` and rejects both forms in a regression. Mach lookup of the live
AppleEvents service returned 0 outside containment and 1100 inside deny-default
containment; no AppleEvents were sent and no window was foregrounded.

The admitted no-fork session-leader lane proves: synthetic read/write/link and
network restrictions, denied fork/setsid, real SDK direct kernel compilation and
execution with stdin `12 30\n` yielding `42`, input EOF/budget/errors/deadline,
physical root death and unrelated-process survival. `physicallySettled` is
explicit and false by default; false retains candidate/scratch obligations.

Non-claims: generic fork-capable tools, supported release-helper certification,
model/functional independent-checker acceptance, external-agent collaboration,
GUI/physical gestures and full App Sandbox/IPC equivalence. Those remain with
their owners and frozen acceptance gates.


The added blocked-input test initially used 1 MiB, which can fit the OS pipe
buffer and complete flush before the target deadline. That RED is preserved in
`owning-gate-input-buffer-red.log`. Its corrected workload uses a declared
bounded 16 MiB input budget to exercise actual blocked flush; root death and
named input failure remained required. The final native gate passed all 27
controls with that fixture and direct Dart Process.start refusal added to the
functional compiler/execution test. Four unchanged harness compatibility
session controls also passed; their log is retained separately.
