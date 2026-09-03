// ignore_for_file: lines_longer_than_80_chars

# ETL scale results — tier 1 (harness package) and tier 2 (whole repo)

Date: 2026-09-02. LLM-free throughout (scripted actor only in the Situation
capstone). Re-run: `dart run pkgs/xsoulspace_agentic_dart_meaning/tool/etl_scale_probe.dart [tier1|tier2]`
or the tests `etl_scale_tier1_test.dart` / `etl_scale_tier2_test.dart`.

## The question this run answers

Do the harness mechanics — meaning tree, ray-cast projection, planning &
decomposition — work WITHOUT a model at repository scale, so that a small
model can be handed bounded tools over that scale? ADR 0022 proved ETL at
task scale (r6); this run proves it at repo scale.

## Measured rows (every number states its source)

| Column | Tier 1 (harness pkg) | Tier 2 (whole repo, pkgs/*) |
|---|---|---|
| files scanned | 231 | 941 |
| symbols (decls) | 2,325 | 10,649 |
| tree nodes (file+symbol) | 2,556 | 11,590 |
| edges (contains/member/imports/refs) | 38,812 | 67,444 |
| scan time | ~70ms | ~290ms |
| tree build time | ~223ms | ~542ms |
| ETL-out fidelity | **2,325/2,325** | **10,649/10,639** → 10,649/10,649 (0 mismatches) |
| cut[point] tokens | 1,598 | 1,557 |
| cut[local] tokens | 2,044 | 2,044 |
| cut[region] tokens | 2,044 | 2,044 |
| cut[summary] tokens | 69 | 70 |
| cut latency | 4–41ms | 6–61ms |
| impact frontier (depth 2, capped 64) | 64 | 64 |
| snapshot save | ~590ms | ~1.2s |
| snapshot restore | ~3.0s | **~18.3s** |
| restore completeness | nodes+edges equal | nodes+edges equal |

Source: `Situation`/cut token estimate = rendered length ÷ 4; build/save/
restore = wall clock in-test.

## Verdicts

1. **The round-trip holds.** ETL-out reconstructs the declaration manifest
   from the meaning tree with 100% fidelity at both tiers — the tree HOLDS
   the code's structure (file, line, kind for every declaration).
2. **Projection is flat — the North Star claim, mechanically verified at
   4.5× scale.** The same target's cut rendered ~identical tokens at 2.5k
   nodes (tier 1) and 11.6k nodes (tier 2): local 2,044 both tiers;
   summary ~70 both tiers. Cut latency 4–61ms — projection does not scale
   with the tree.
3. **Decomposition is deterministic and bounded.** Reverse-reference
   closure + `projectPlanFrontier` under a token budget; same input → same
   frontier (two-build determinism asserted).
4. **Text and matrix ETL feed the same tree.** ADR 0022 sections →
   requirement nodes with criteria; AE canonical matrix →
   `canonicalToMeaningTree` → concept/feature nodes. One tree, three
   sources (code, text, matrix) — the agentic-executables charter, LLM-free.
5. **The small-model capstone passes.** Actor + Goal + 30 ETL beats + plan
   steps at tier-1 scale → one scripted decision → `Situation.tokensUsed`
   ≤ 4,000. The model-visible cut stays bounded while the world holds the
   whole package.

## Findings (flaws the probe surfaced)

1. **FIXED — stable-id collisions.** Same-name declarations in one file
   (private handlers in separate class scopes) collided on the
   `sym_<file>_<name>` id and threw. Fixed with per-file ordinal
   disambiguation in `buildMeaningTreeFromCode`. (Found at tier 1 build.)
2. **FIXED — impact frontier soft cap.** `HarnessLoop` reaches 1,020 nodes
   at depth 2 — real frontiers overflow a soft cap, and a model must never
   receive an unbounded frontier. Fixed: hard cap with degree-ranked
   selection (most-referenced first).
3. **OPEN (critical for repo-scale persistence) — snapshot restore is
   super-linear.** 38.8k edges restore in ~3.0s but 67.4k edges take
   ~18.3s (~2.3× edges → ~6× time). Save is fine (~1.2s). Suspect:
   per-edge entity resolution or facet-index rebuild in
   `restoreWorldSnapshot`. Owner: snapshot machinery; must be O(n) before
   snapshot/restore is part of a repo-scale loop.
4. **OPEN (minor) — AE matrix wire shape.** `canonicalToMeaningTree`
   expects a `features` key (canonical-matrix v1); hosts guessing `rows`
   get an empty export silently. The wire should fail loudly on unknown
   shapes (AE-side, `test_wire`-adjacent).
5. **OPEN (minor) — scanner scope.** The structural scanner reads
   dart-formatted sources (indentation-0 decls, 2-space members) and skips
   generated files; exotic formatting or non-Dart languages need the AE
   adapters, not this scanner. Fidelity is measured against the same
   scanner, so it proves round-trip integrity, not parser completeness —
   the analyzer-based completeness check is the P4/J3 span-edit path.

## What this means for the North Star

The mechanism stack (meaning tree + ray-cast projection + derived
decomposition) now has repo-scale, LLM-free evidence: a 2–4k model never
needs to see more than ~2k tokens of a 67k-edge structure, the structure
is reconstructable, and the decomposition it acts on is bounded and
deterministic. The remaining scale blocker is snapshot/restore
performance (finding 3), not projection.
