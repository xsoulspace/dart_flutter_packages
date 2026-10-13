# Tooling runtime

One extracted implementation of `runBounded`, `stopProcessTree` and
`awaitProcessSettlement`, actively used through harness compatibility exports by
host coding execution/checkers and Last Answer runtime preparation.

The host supplies admission, executable, arguments, CWD and limits. On POSIX a
trusted system helper establishes an acknowledged session before target exec;
deadline ownership continues through target/root exit, output drain and live
process-group membership. Successful target output and argv are unchanged.
Missing prerequisites and unobserved/escaped pipe lifetime are named failures.
Windows retains the existing root-only limitation.

The package also owns `WorkspacePathPolicy` and the cooperative, reentrant
`FileLockTable`. Path resolution checks both the lexical request and symlink
resolution against the current injected policy; missing descendants use the
nearest existing ancestor. Construction retains the original root-directory
creation behavior. The harness keeps its ECS resource and write gateway as
adapters over these mechanics.

This package grants no authority, creates no scheduler or transaction and has
no file-content writer. Path policy and cooperative locks are not OS isolation:
hard-link aliases and concurrent replacement require a qualified host boundary.
Generic process groups/sessions require a separately qualified isolation boundary. `ok` requires successful exit and no
reported settlement problem or survivors; it is not semantic task acceptance.


`MacOsCandidateVerifier.verifyCandidate` supplies the explicit
`macos_no_fork_candidate_v1` capability. Its deny-default native profile denies
Mach/AppleEvents, network and fork; a trusted launcher execs the target in its
session-leader PID. Each call grades synthetic containment controls first.
Host-built candidate/read roots, private HOME/TMPDIR, bounded stdin/EOF and
physical settlement remain separate from promotion and semantic acceptance.
The result's `physicallySettled` must be checked before candidate cleanup; false
retains scratch and the outer candidate obligation. There is no uncontained
fallback. Fork-required commands refuse by name before launch.

For Dart use direct `dartaotruntime` + SDK `gen_kernel_aot.dart.snapshot` with an
explicit VM platform, followed by `dart --disable-dart-dev` for kernel execution.
Ordinary fork-capable `dart compile`, Flutter builds and generic shell chains
remain unsupported here. The deprecated native utility needs a supported,
qualified release replacement; this adapter is not general OS isolation or
release certification. See DFP ADR 0066 and the package qualification record.
