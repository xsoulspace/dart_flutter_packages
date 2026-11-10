# PREREG-SPEED — experiment-speed laws for STAGE-3+ arms

Status: FROZEN 2026-11-10 (owner: "do all recommended coding for speedup menu,
but do not run it"). Applies to arms whose preregs are written FROM this row
forward. In-flight/frozen protocols (A2 capcurve 32k, stage-2 cells, P-2/P-2b
paper comparability) are UNTOUCHED — mid-flight protocol changes void
verdicts, so every law here carries its integration boundary explicitly.

The speedup menu this freezes (from the 2026-11-10 analysis): loop-proxy
early stop, per-row chunking, 4-bit screen → bf16 certify, in-memory delta
merge, sequential early-stop with always-valid CIs, storage-budget field.
Combined projection: a ~2 h stage → ~10–20 min, same oracles and
denominators.

## L1 — Loop-proxy early stop (the big one, ~30× on loop cells)

The frozen detector (PREREG-G §3: 4-gram / window 64 / threshold 3) fires
within ≤128 tokens of a loop attractor; generating to a 32k cap to "confirm"
what the detector already knows is the single largest waste in the program.

Frozen policy (constants; a change = addendum):
- `T_PROXY = 1024` (proxy window bound), `F_EARLY = 3` (detector fires
  inside the proxy bound), `MIN_TOKENS = 256` (never classify before this).
- During generation: once `generated ≥ MIN_TOKENS` and the detector has
  fired `F_EARLY` times at positions all `≤ T_PROXY`, generation STOPS and
  the row is classified **LOOP_PROXY** with `proxy_stop_at = t`.
- Classification taxonomy (frozen): `LOOP_PROXY` | `LOOP_CAP` (hit the real
  cap) | `EOS` | `TRUNCATED` (budget stop). LOOP_PROXY is a NAMED PROXY —
  it is NEVER merged with cap_hit in paper-comparability arithmetic.
- Exempt arms: every P-* comparability arm (they owe the paper a true 32k).
- Implementation: `tool/runs/wm_generate_speed.py` (python-first, custom
  step loop, single process, model loaded once, per-row output files) — the
  ONLY sanctioned generation entry for long caps in stage-3+ arms.

## L2 — Per-row chunking / per-row outputs (progress + resume)

Long-cap rows (cap ≥ 4096) always produce one output file per row, written
immediately on row completion (the 2026-11-10 blind-wait lesson: the frozen
batched generator is progress-blind mid-flight). Runners resume by skipping
rows whose files exist. Implemented in `wm_generate_speed.py`.

## L3 — 4-bit screen → bf16 certify (V-5-shaped, ~2–3× on screening)

Screening legs may run on a 4-bit cast (bandwidth-bound decode ≈ bytes/4).
Screen verdicts NEVER certify (propose-only law): the winner set = ALL arms
passing the pre-registered screen floor (never top-k, never select-best);
every winner is re-run and certified on bf16. The screen's ROC (and
`evals_skipped_per_false_negative`) is measured and receipted — the V-5
audit shape. Quant is already an axis of the certification key (§5 PREREG-G):
a screened winner certified on bf16 carries the bf16 key, and the screen
arm's verdict carries the 4-bit key. Implementation:
`tool/runs/screen_certify.py` (pure core unit-tested; the 4-bit checkpoint
resolves at run time — a missing store is the named refusal
SCREEN_MODEL_MISSING, never an auto-download).

## L4 — In-memory delta merge (mirrors banned, ~1 min/sample + 3.2 GB/sample)

Materialized mirror stores are BANNED in stage-3+ arms. The merge happens in
memory at load: python reference `tool/runs/delta_merge.py` (column math:
`W[:, j] += scale · direction` per chosen column — the frozen apply_delta
semantics verbatim), Rust twin `native/mlx_native/src/delta_sidecar.rs`
(`SpecDelta::apply_to(params)` mirroring the lora.rs merge-at-load pattern).
Parity gate: the FIRST live run must receipt a merged-tensor digest
python == rust (the qwen35_parity pattern); until that receipt exists the
Rust path stays screening-only. Quantized bases keep the lora.rs refusal
(dequant→merge→requant is a different, refused path).

## L5 — Sequential early-stop with always-valid CIs (~30% on decisive arms)

Cell banks may stop early when a time-uniform (always-valid) CI separates
the running rate from the prereg floor. Implementation:
`tool/runs/seq_stop.py` — Hoeffding mean-bound form
`halfwidth(n, α) = sqrt(ln(2/α) / (2n))`, valid uniformly over n (optional
stopping priced, per the statistical constitution, not hidden). The stop
rule and α are FROZEN in each arm's prereg before the first cell; a
post-hoc α is a new row. Non-decisive banks simply run to n (the rule never
forces a wait).

## L6 — Storage-budget field (mandatory)

Every new prereg carries `predicted_peak_scratch_GB` with the reclamation
plan named. (SM-1's original shape implied ~96 GB of mirrors; the field
would have caught it at freeze time.)

## L7 — Batched decode: FUTURE ENGINE PRERG (honest re-scope)

The receipted 1.93×@B8 fused batch lives on the DENSE qwen path
(`qwen_batch.rs`/`qwen_fused.rs`). The qwen3_5 hybrid tower is DOCUMENTED
single-sequence, batch-1 (`qwen3_5.rs` header: ssm_mask None path; the
packed GDN kernel is single-sequence). Batching qwen3_5 = new GDN-batched
kernels + a batch-parity gate (fused kernels may reorder float reduction
order; bitwise identity must be PROVEN before batched decode feeds any
certification cell). Re-scoped as its own future prereg; no scaffold tonight
(a single-sequence "batch bin" would be fake).

## Non-claims

No frozen verdict changes. Speed laws never alter oracle semantics: LOOP_PROXY
is a named proxy, never cap-hit; screen verdicts never certify; early-stop α
is pre-declared; paper comparability arms keep their true caps. Absolute
wall-ms remain non-claims (POWER.md).
