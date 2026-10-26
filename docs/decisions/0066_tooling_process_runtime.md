# ADR 0066: One reusable tooling process runtime

Status: Accepted
Date: 2026-10-13
North Star impact: applies

## Context

Host coding, independent checkers and Last Answer preparation already use the
harness bounded process mechanism. It depended on the engine package despite
having no ECS or inference dependency. Independent review reproduced a defect:
an immediate root exit cancelled the deadline while a child retained output
pipes. The run exceeded its deadline and reported a normal exit.

## Decision

After repairing that native owner and grading original and new controls, move
the entire implementation into `xsoulspace_tooling_runtime`. Existing harness
lifecycle import paths re-export that single library; host and product callers
retain their execution, authority and resource ownership. This is IO tooling,
separate from the pure materialization core of ADR 0065. No second executor,
scheduler, journal, filesystem writer or model-provider dependency is introduced.

POSIX execution establishes an acknowledged private session through an automatic
trusted system helper (protocol **p1**, Perl reference in
`pkgs/xsoulspace_tooling_runtime/tool/owned_session_p1_leader.pl`; contract in
`doc/owned_session_p1.md`). A close-on-exec pipe distinguishes target spawn
failure before notifying observers. The **owned** leader anchors the PGID,
keeps its own stdin on `/dev/null`, and talks to the host over a **Unix-domain
control socket** in a `0700` temp directory (authenticated with the launch
marker nonce). Target stdin/stdout/stderr stay exact. The host never SIGKILLs
the leader directly for group teardown: it sends `term` / `kill` commands on the
channel; the leader runs `kill(0, SIGTERM)` then `kill(0, SIGCONT)` for `term`,
and `kill(0, SIGKILL)` for `kill`. `Process.kill` on the leader is a last
resort only. Channel EOF makes the leader kill its group and exit (host-death
orphan guard). The host watches the group with bounded `ps` and sends `settle`
when only the leader remains after the main target's `exit:<waitstatus>` notice.
Missing observation is `unsettled:<reason>`, never silent certification. External
cancellation uses `stopOwnedGroup` / the retained registration, never a guessed
tree on a possibly recycled pid. Observed group disappearance is terminal: a
recycled ID is never reacquired. There is no stale-snapshot per-pid fallback.

**`singleProcessSession`** has no separate leader: the helper execs the target
in the session-leader PID (unchanged handshake).

### Implementation relocation (oka)

Process mechanics (p1 leader, control channel, signal routing) will move to a new
**oka** leaf package **`oka_process`** without changing the argv/socket contract
documented in `doc/owned_session_p1.md`. This package retains **admission
policy** — deadlines, `runBounded`, harness lifecycle exports, and
`stopOwnedGroup` registration — until callers adopt `oka_process` directly.

Missing helper or process observation refuses by name. Windows retains its
existing root-only limitation. Descendants creating other groups/sessions and
filesystem/network effects require separately qualified isolation. An escaped
inherited pipe or unavailable observation is named unsettled, not certified as
process death or semantic acceptance.

## Consequences and evidence

Actual consumers are host coding execution, canonical command checkers and Last
Answer product runtime preparation, through compatibility exports. The package
uses Dart IO and `meta`, with no ECS/Flutter/provider dependency.

Original RED evidence and repair controls are retained under harness
`docs/evidence/conventional-local-coding-2026-10-13`. Fourteen matched native
controls passed before relocation, including inherited/closed pipes after root
exit, external cancellation after root death, unrelated-process preservation,
spawn-error/observer behavior and exact argv/stderr. Owning package gates and
post-relocation consumer checks remain required; this does not qualify a general
OS sandbox, ordinary real-model coding, external collaboration or release.


## Candidate verification qualification (2026-10-13)

`MacOsCandidateVerifier` is a host-built, capability-labelled
`macos_no_fork_candidate_v1` adapter. It admits a private, exclusively owned
candidate and explicit read-only SDK/cache roots. It never accepts a model
profile or silently retries outside containment. Before each command a harmless
synthetic self-test grades root writes, out-of-scope content reads/writes,
hard-link creation, a live localhost listener, denied fork and denied setsid.
The target gets private HOME/TMPDIR and a scrubbed environment.

The profile denies by default, with process exec, metadata and system bootstrap
reads plus the declared read/write roots; it grants no Mach lookup, AppleEvents,
network, or process fork. System content reads use `/System/Library`, not the
entire `/System` Data-volume namespace. Existing candidate hard links refuse;
symlink/volume aliases are checked by the OS policy. The host must retain
exclusive candidate ownership throughout audit and execution.

A fork-denied command alone was insufficient with the old supervised launch:
the main child could itself create a new session. The opt-in
`runBounded(singleProcessSession: true)` trusted launcher instead establishes a
session and execs the admitted target in that exact session-leader PID. Kernel
session-leader rules prevent its setsid/setpgid escape; denied fork prevents new
children. Readiness precedes exec in this mode; normal supervised exec-ack and
all existing callers' defaults remain unchanged.

`CandidateVerificationResult.physicallySettled` is explicit and false by
default. Input/output and root lifetime use one deadline; bounded host input is
copied, flushed, closed, and failed writes/flush/close are named in
`BoundedRunResult.inputProblem`. Input failure prevents `ok` even after exit zero.
Unproven settlement retains scratch storage and prevents the outer host from
deleting the candidate, promoting it, or clearing its quarantine from a model
argument. The outer transaction owner retains that reconciliation obligation.

The useful current Dart lane invokes `dartaotruntime` with the SDK's
`gen_kernel_aot.dart.snapshot` and explicit VM platform, then executes the kernel
through `dart --disable-dart-dev`. It supports actual stdin vectors and functional
checks; compilation alone is not acceptance. The CLI `dart compile`, Flutter
builds and arbitrary fork-capable shell/tool chains are not qualified by this
adapter. `requiresProcessFork: true` refuses before launch.

### Reuse and remaining release route

The primary [Anthropic sandbox-runtime implementation](https://github.com/anthropics/sandbox-runtime/blob/main/src/sandbox/macos-sandbox-utils.ts)
uses native Seatbelt with deny-default bootstrap rules and opt-in Mach/AppleEvents
and Unix sockets. Its Node runtime, proxy server and broad optional IPC/service
allowances are not needed for this offline no-fork adapter. Reuse the native OS
mechanism and contract concepts without making users install Node or claiming
that this smaller lane is the complete upstream runtime.

`sandbox-exec` remains [deprecated](https://developer.apple.com/forums/thread/661939).
Darwin SDK `sys/event.h` states NOTE_TRACK/NOTE_CHILD stopped being supported in
macOS 10.5; the rejected tracker prototype was removed. Process-group snapshots
cannot qualify reparented, detached, closed-stdio descendants. General
fork-capable execution remains an explicit requirement, not a completed lane.
A supported release route may compose Apple's
[Virtualization framework](https://developer.apple.com/documentation/virtualization/creating-and-running-a-linux-virtual-machine)
with app-managed guest images and
[read-only directory shares](https://developer.apple.com/documentation/virtualization/shared-directories),
no host network device by default, and guest-machine termination as the physical
settlement boundary. That requires image, signing/entitlement, startup-cost and
cross-platform qualification; no VM or image was installed by this extraction.

Native controls cover canonical and Data-volume aliases, pre-existing/new hard
links, fork and setsid denial, live network and AppleEvents lookup oracles,
actual SDK kernel compilation/execution with stdin and expected output, input
budget/EOF/error/deadline behavior, and unrelated-process preservation. They do
not prove release readiness, arbitrary IPC equivalence, real-model coding or
external-agent acceptance. The original generic process controls stay frozen.
See [the qualification record](../../pkgs/xsoulspace_tooling_runtime/docs/evidence/2026-10-13/README.md).
