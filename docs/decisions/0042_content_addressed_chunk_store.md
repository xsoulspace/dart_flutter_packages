# ADR 0042: Content-addressed chunk store — native binary deltas for large files

- Status: Accepted
- Date: 2026-09-29
- North Star impact: `amends` — replaces the opaque-binaries row of
  [0010 §5](0010_mesh_sync_architecture.md) ("object-level LWW at provider
  layer") with manifest-level LWW over an additive content-addressed chunk
  store. The mesh, kernel, and capability seams are otherwise unchanged.
- Builds on: 0010, 0011; channel crypto per [0039](0039_mesh_session_aead_channel_crypto.md)
- Related: `universal_storage_live_apply` README (content-addressed blob
  journal plan — this ADR is its general form); Epic Games Lore system
  design (independent external validation of the same architecture).

## Context

Binaries are unrepresentable today: the provider contract is `String`-only,
no chunking, content addressing, or diffing exists anywhere in the workspace,
CloudKit hard-fails above inline size limits, and git conflicts resolve
whole-file `--ours`/`--theirs`. Object-level LWW re-transfers entire assets
after every edit and destroys the loser. Game development (textures, meshes,
audio — often re-exported incrementally at hundreds of MB) and AI-agent asset
workflows need binary deltas and recoverable conflicts. Measured demand comes
from all three mesh products; last_answer's roadmap already names image/video
blocks.

## Decision

### 1. New package family: chunker + content-addressed store + manifests

`universal_storage_chunks` (final name at implementation), pure Dart per the
0010 tooling constraint:

- **Chunking**: content-defined chunking via FastCDC (gear hash), 64 KiB
  average / 32 KiB floor / 256 KiB ceiling — parameters adopted from Lore's
  published design. Same bytes → same chunks regardless of offsets; an edit
  re-chunks only near the edit.
- **Addressing**: `sha256` of the *uncompressed* chunk bytes (Lore uses
  BLAKE3; the pure-Dart constraint favors `cryptography`/`package:crypto` —
  BLAKE3 remains an option if a maintained pure-Dart implementation appears).
- **Compression**: zstd per chunk, orthogonal to addressing (hash-then-
  compress layering). Pure-Dart zstd is an open risk: v1 may ship
  uncompressed chunks or an FFI codec behind a fallback — the address never
  depends on the codec.
- **Store**: append-only packfiles with an address→offset index; chunks are
  immutable, so the store is additive and replicas converge by set-union —
  no conflict logic below the manifest.

### 2. Manifests are kernel docs

A file manifest (ordered chunk addresses + total length + content hash) is an
ordinary `ConvergenceDoc` value: it rides existing anti-entropy, snapshots,
compaction, and the LWW policy unchanged. Binary LWW losers keep their
manifests staged through the existing conflict workflow — recoverable, never
silently destroyed. The kernel stays byte-blind: ops carry manifest docs
(small), never chunk payloads.

### 3. Transfer and dedup

Chunk frames ride the existing `MeshSession` (AEAD per 0039): parallel,
resumable, per-chunk. Upload dedup across stores requires **proof of
possession** of the bytes, never hash-knowledge alone (adopted from Lore) —
a peer that knows a hash but not the bytes cannot make a replica fetch or
skip anything.

### 4. GC and capability seam

- GC is a reachability scan over known manifests plus a grace period,
  conservative exactly like 0011 op retirement: a chunk referenced by any
  replica's live manifest is never collected.
- A capability-gated `BlobStore` seam lands parallel to `StorageProvider`;
  the `String` contract is untouched. The conformance suite grows blob
  scenarios: dedup across writes, partial re-upload, crash mid-upload, GC
  safety, and convergence of concurrent manifest writes.

### 5. Sequencing

1. **Workspace vacuum** (first consumer, zero product risk): snapshot +
   hardlink-checkout tool over `~/xs`, deduping repos, history, and build
   outputs; cold data offloads as chunks.
2. Mesh provider blob namespace (bins flow over the mesh).
3. last_answer image attachments (human + agent vertical slice).
4. ecsly assets.

## Property obligations

- Chunking determinism and edit locality (property tests).
- Store union-commutativity and idempotence.
- Manifest LWW convergence with retained losers.
- Benchmarks (stand up `pkgs/benchmark`): CDC throughput ≥ 100 MB/s in an
  isolate; dedup ratio on a synthetic asset-reexport series; transfer size
  vs whole-file baseline.

## Non-claims

- No binary CRDT: opaque formats get no semantic merge. Policy is LWW with
  retained losers; live coordination is deferred to [0043 track 3](0043_storage_shrink_exploration_tracks.md).
- Not git LFS: no git server dependency; the store is mesh-native.
- Large *text* files stay kernel docs (RGA lanes). Manifest-backed text is
  deferred with a recorded trigger: op payload size for ≥ ~1 MiB text docs
  becoming a measured problem.
- Distributed GC stays out: v1 GC is local-conservative; a global watermark
  protocol waits for a deployment that needs it.

## Consequences

- 0010 §5's binary row is replaced; no other row changes.
- `universal_storage_interface` gains one capability flag; no provider is
  forced to implement blobs.
- The same primitive serves the workspace vacuum and future cache budgets —
  one implementation, three consumers.
