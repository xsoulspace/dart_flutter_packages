# ADR 0070: Compressed incremental index segments — one CAS substrate for large machine indexes

- Status: Accepted direction. Implementation gated per package (§Ladder).
- Date: 2026-10-17
- North Star impact: `amends` [0042](0042_content_addressed_chunk_store.md) —
  builds the explicitly-deferred "compression is a later layer" on the chunk
  store, and adds a segment/manifest layer above it. The kernel, mesh, and
  capability seams are unchanged; a new index family composes the existing
  primitives instead of forking them.
- Builds on: 0042 (content-addressed chunks), 0011 (op-based convergence),
  0047 (world urns / zone census), 0050 (realtime plane)
- Measured on: the codemap/gitnexus index fleet, 2026-10-17 — per-repo
  `.codemap/index/` trees of **3.5–4.2 GB** each (flat uncompressed-JSON
  `extraction/` of 65k+ entries), against a **617 MB** global content-
  addressed fact store for the same sources. Roughly 85% of today's index
  footprint is duplication (per-repo, per-generation copies) and missing
  compression, not information.

## Context

Machine indexes (code graphs, symbol extracts, search terms) are the
largest unsyncable data on agent machines. Today they live in per-tool
stores: gitnexus holds its graph in LadybugDB (an embedded Cypher
database), codemap holds extraction JSON per repo per generation. Three
failing properties follow:

1. **No dedup across repos or generations.** The same file's extract is
   stored once per repo copy and once per index generation. 617 MB of
   global facts becomes 8+ GB of local indexes.
2. **No compression anywhere.** The records are small structured JSON —
   exactly the shape zstd with a trained dictionary compresses 5–15×.
3. **Not syncable.** Database files (LadybugDB pages, SQLite) are opaque
   single-writer artifacts; two machines cannot union them, and rsync of a
   live database is corruption roulette.

The requirements are simultaneously: extreme compression, incremental
updates, lightning-fast reads (graph adjacency at memory bandwidth, term
lookup in microseconds), high parallelization (extraction and compaction
across cores), and syncability (two machines converge by exchanging
bytes, offline-first, like the rest of this family).

## Decision

Do not build (or keep) a database as the store. Build a **content-
addressed segment store**: the CAS from 0042 is the only durable truth;
everything query-shaped is a derived, rebuildable access plane. Six
layers:

### 1. Segments and manifests (new `universal_storage_index`)

An index is an ordered list of **segments**. A segment manifest records:
the chunk addresses of its columnar record groups (the CAS pointers from
0042), per-group min/max/bloom filters, record counts, and the extraction
generation. The manifest is a plain JSON kernel-doc value — the same
shape as `ChunkManifest` — so it rides LWW convergence, zone census
(`meta` already anticipates blob manifests), and ordinary providers. One
index = one `world://` member whose value is the manifest; history is
just prior manifests.

### 2. Compression (new `universal_storage_zstd`, decorator in `universal_storage_chunks`)

`CompressedChunkStore` wraps any `ChunkStore`: on disk, chunk files carry
a small header (codec id, uncompressed length) and zstd-compressed bytes,
optionally with a **trained dictionary per index family** (one ~100 KB
dictionary shared by a whole index kind is where most of the win on
small JSON records lives). The address law from 0042 is preserved and
tested: **the address is sha256 of the UNCOMPRESSED bytes and never
depends on the codec** — stores with different codecs interoperate, and
re-compression is a local, non-syncing operation. Wire transfer may add
dictionary-aware framing later without touching addresses.

### 3. Increments and deltas (extraction protocol)

Extraction is keyed by `(path, content-hash)`: only files whose content
hash changed since the last generation are re-extracted. Because CDC
chunking splits at content-defined boundaries (already deterministic in
`ContentDefinedChunker`), an unchanged region of a changed file yields
the SAME chunk addresses — cross-revision dedup is free. On top of that,
segment revisions MAY form delta chains (zstd patch-from against the
previous segment's chunks) with the oka-artifacts law: keep the delta
only while it stays far below snapshot cost (measured there at 0.03%
per build), else write a fresh snapshot segment. Incremental runs then
cost bytes ∝ changed files, and sync transfers bytes ∝ new chunks.

### 4. Parallelism (pipeline, not structures)

Extraction is a pure function `file bytes → records`; run it on an
isolate pool (N−1 workers) with per-file tasks. Compaction (merging k
segments into one) parallelizes per record group; every merge is
copy-on-write into new CAS chunks, so readers never lock. No structure
in the store needs coordinated mutation — the only serialized step is
publishing the new manifest, which is one LWW op.

### 5. Access planes (derived, rebuildable, local-only)

The store never answers queries directly; each machine materializes the
planes it needs from segments, and only those:

- **Graph plane**: CSR (compressed sparse row) arrays — sorted node ids,
  Uint64 offsets, Uint32 neighbors. A 10M-edge code graph is ~80 MB raw,
  a few MB compressed, and mmap-backed adjacency iteration runs at memory
  bandwidth with zero per-hop object allocation. This is the read path
  gitnexus today gets from LadybugDB.
- **Term plane**: FST dictionary + sorted postings chunks for BM25-style
  search.
- **Relational plane (optional)**: materialize SQLite — or LadybugDB
  itself — FROM segments when a tool genuinely needs Cypher/SQL. It is a
  cache with a rebuild command, never the source of truth, never synced,
  always safe to delete.

This is the answer to "LadybugDB or our own format": **our own format
for storage; LadybugDB demoted to an optional local accelerator.** An
embedded Cypher engine is the wrong durable substrate (opaque pages, no
dedup, no union merge) and simultaneously unnecessary on the hot path
(CSR answers traversal; the graphs are small enough that a Cypher
frontend over materialized state is a comfort, not a requirement).

### 6. Sync (free by construction)

Manifests converge through the existing kernel (LWW per member, or
convergence lanes if manifest history matters). Chunks transfer via
`MeshChunkExchange`, any `StorageProvider`, or plain rsync of the store
directory — content addressing makes every mechanism a set-union CRDT:
two machines that extracted the same corpus independently hold the same
chunk set and differ only in manifests. GC is reachability from live
manifests (`ChunkedBlobStore.reachableAddresses` already computes it);
a chunk only dies when no manifest anywhere references it.

## Package ladder

1. `universal_storage_zstd` — ffi codec seam (first ffi codec in the
   workspace; dart:ffi precedent already exists in filesystem's POSIX
   bindings), graceful degradation when absent.
2. `universal_storage_chunks` — FastCDC dual-mask normalization, bulk
   buffer fast path, `CompressedChunkStore` decorator, conformance: an
   address computed under codec A must resolve under codec B.
3. `universal_storage_index` — segments, manifest codec, dirty-file
   planner, isolate-pool extraction harness, compaction scheduler,
   reachability GC, CSR + term planes.

## Alternatives considered

- **Keep LadybugDB as the store, tune it**: rejected — opaque
  single-writer pages cannot union across machines or dedup across repos;
  the measured 85% overhead is structural, not tunable.
- **SQLite as the store**: excellent local relational cache (kept as the
  optional relational plane), wrong durable substrate for the same
  opacity reasons, and no CDC dedup.
- **Build a full query engine over segments**: rejected as mechanism-
  becoming-mission; planes answer the actual access patterns, and a
  planner can come later over the same segments if ever needed.
- **Plain zstd of whole index files (no CAS)**: one line of code, but no
  dedup, no incremental sync, no parallel compaction — it compresses the
  duplication instead of removing it.

## Consequences

- Fleet storage target: the ~8 GB index estate collapses toward the size
  of its deduplicated, compressed content (order of the 617 MB fact
  store, minus its own JSON overhead) plus small manifests; sync traffic
  per incremental run drops to new-chunk bytes only.
- Readers gain predictable latency: mmap planes, no query planner, no
  page cache surprises from a second database engine.
- Tooling that wants Cypher keeps it — as a disposable local view.
- New obligations: dictionary training must be deterministic per family
  (else addresses stay stable but compressed sizes diverge harmlessly);
  compaction must be budgeted (it is background, cancellable work); GC
  needs a manifest liveness notion per device (a chunk referenced by any
  LOCAL manifest lives, regardless of remote state).
