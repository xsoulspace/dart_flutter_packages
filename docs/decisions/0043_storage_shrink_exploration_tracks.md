# ADR 0043: Storage-shrink and tooling exploration tracks

- Status: Accepted (exploration record)
- Date: 2026-09-29
- North Star impact: `clarifies` — records research tracks with triggers and
  kill criteria; amends no boundary and creates no packages, harnesses, or
  probes until a trigger fires (AGENTS.md default-no-harness rule).
- Builds on: [0042](0042_content_addressed_chunk_store.md) (chunk-store
  sequencing), [0031](0031_presence_link_topology_and_session_foundation.md)
  (presence), [0010 §2](0010_mesh_sync_architecture.md) (node standing).
- Measured context: on the reference dev machine, unique source text across
  the workspace is ~1–2 GB while regenerable build artifacts, tool caches,
  and leaked automation temp data account for hundreds of GB (a single
  Chrome-for-Testing automation leak held 118 GB of code-sign clones; oka's
  `oka_engine_*` temp dirs leak by construction). Two conclusions follow:
  storage discipline is mostly tooling hygiene, and one content-addressed
  chunk primitive can serve product, workspace, and cache-budget roles.

## Tracks

Each track names its trigger, first experiment, and kill criteria. Tracks
produce ADR amendments or measured results, never speculative packages.

### 1. Workspace vacuum (active — first 0042 consumer)

- Hypothesis: chunk-store snapshots + hardlink checkouts dedup `~/xs`
  (repos, git history, build outputs) enough to matter and make cold-data
  offload cheap.
- First experiment: snapshot `dart_flutter_packages`, measure stored ratio
  vs `du`, and hardlink-checkout equivalence.
- Kill: ratio < 1.5× on the working set excluding build outputs → keep the
  tool for offload only, or drop it.

### 2. codemap pattern projection

- Hypothesis: codemap's duplication engine (exact/normalized/structural IR
  fingerprints, `meaning-collapse`) can emit duplicate families as
  projections worth acting on across this monorepo.
- Boundary: semantic dedup stays an **explicit refactor aid** (source layer).
  It is never an implicit storage-layer transformation; lossless storage
  dedup is 0042's job.
- First experiment: add an approximate `pattern_shaped` basis and a
  `codemap.pattern_projection` emitter upstream (in `~/xs/codemap`); run on
  this monorepo; act on one family via `meaning-collapse`.
- Kill: consolidation payoff flat across two runs on real code → close with
  a negative-result note.

### 3. Presence-based soft locks for unmergeable binaries

- Hypothesis: Lore-style server locks map onto `MeshPresenceSession` — a
  doc-scoped presence session on an asset is an advisory lock; sync declines
  auto-LWW while a live lock-holder exists and stages the conflict instead.
- Trigger: first real concurrent asset-edit conflict in last_answer
  attachments or ecsly assets.
- Kill: manifest-LWW plus retained losers proves sufficient in observed
  usage → record and close.

### 4. AST-aware chunk boundaries

- Hypothesis: syntax-informed chunking beats FastCDC dedup on rename-heavy
  code history (byte-level CDC misses alpha-renames and reformatting).
- First experiment: offline study over two repos' git history comparing
  chunk-count and transfer volume, FastCDC vs syntax-aware splits.
- Kill: < 1.3× improvement → record the negative result; FastCDC remains the
  only chunker.

### 5. Lore bridge node

- Hypothesis: an Epic Lore local-mode server joins the mesh as a bridge node
  with archive/export standing (0010 §2: a node with a role, never an origin
  or merge authority).
- Trigger: game-asset sizes exceed relay comfort, or external-team interop
  requires it.
- Kill: two breakages from Lore pre-1.0 format churn → drop; git_offline
  remains the archive path.

### 6. WebRTC mesh transport (parked)

- Standing: vosges measured TURN-class paths at 30–150 ms RTT and chose
  relay + session AEAD; that decision stands.
- Trigger: a P2P NAT-traversal requirement with no relay infrastructure
  available. Until then the `WebRtcMeshTransport` idea stays purely additive.

## Non-claims

- No track creates a package, action, probe, or benchmark before its trigger
  fires.
- Machine hygiene (temp sweeps, cache budgets, the `just sweep-machine`
  recipe, oka eviction fixes) is recorded tooling, not an ADR track — it
  needs no decision record beyond the justfile and the owning repos.
- No claim that semantic source dedup shrinks working storage measurably;
  measured evidence says it does not.

## Consequences

- 0042's sequencing references track 1 as its first consumer.
- Exploration outcomes amend this ADR (trigger fired / killed) rather than
  accreting new records.
