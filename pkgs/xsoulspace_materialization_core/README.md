# Materialization core

Deterministic Dart op-chain compilation, host-resolved expression descriptions,
resolved edit inputs, format map-node data and typed Markdown/configuration payload admission.
Extracted from the harness workspace; its existing imports re-export these
implementations and its native editor retains all mutation and recovery.

`compileOpChainBody` constructs a callable body. `materializeDartGraph` constructs
file contents from an already resolved graph and explicit callable signatures.
Neither entry point reads or writes files, grants authority, or establishes
behavioral equivalence. In particular, the existing numeric-only VM `add` and
Dart string composition have different coverage; extraction does not widen it.


`TextChangeCandidate` stores a portable immutable text candidate, independent of
its native journal. The host supplies a canonical resolved workspace identity,
origin task and optional actor reference, observed source (including absent
files), intended changes, and verification description/JSON receipts. Absence
(`null`) remains distinct from empty text. Changed paths require observations;
per-file no-ops and malformed paths refuse. Receipt fields are data, not fresh
verification or consent authority.

Every object level has sorted keys in `canonicalJson`, which the native host may
hash with its existing crypto implementation. Exact text and nulls survive.
Nested receipts and maps are copied and frozen; `toJson()` returns a fresh mutable
copy. Constructor/fromJson require a host-provided `maxDecodedBytes` UTF-8 JSON
budget; nesting, cycles, unsupported values, malformed Unicode and nonfinite
numbers refuse. `decode` accepts only the canonical version-1 representation,
rejecting whitespace/duplicate-key ambiguity; use `fromJson` to normalize an
already parsed object. This is the package's deterministic Dart JSON contract,
not a claim of RFC 8785/JCS or another runtime's number encoding.

This layer cannot resolve symlinks, grant a workspace, issue actor authority,
run checks, promote, recover or replay mutations. The native owner compares
workspace identity, enforces current policy/revisions, independently verifies,
and applies through its existing journal. Stored evidence cannot bypass those
fresh controls. No IO, provider, ECS or hash dependency was introduced.
