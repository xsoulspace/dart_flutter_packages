# WS-1 live replay summary (2026-11-06)

**Verdict: PASS** — the A3 plant-1 (arm-002) recovered removal edit, converted
to a typed patch artifact, replays A3's recorded mirrors **bit-identically**.
Durable record: `receipts/WS1-replay.jsonl` (hash-chained via the frozen lib
ledger; 5 rows: 2 `edit`, 2 `replay`, 1 `ws1-verdict`; CHAIN_INTACT).

## What was replayed

- Source edit: arm-002 `repair_spec.json` (recovered proposer directions from
  `recovered.json`, scale −4.8 = negated plant scale, plant columns) — the
  removal mirror R that certified in A3 (loop M→R −0.33, task +0.41).
- Typed patch: `bridge.sidecarDeltaToPatch(spec, baseFingerprint: <recorded
  plant-mirror shard digest>)` → rank-1 column-window `PatchEntry` per tensor;
  canonicalized back via `patchToSidecarSpec` (round-trip checked) and
  materialized through `patch_algebra.apply` against the REAL rebuilt-M tensor
  values with `actualFingerprint` = rebuilt M store digest (a moved base would
  refuse NAMED `STALE_PRECONDITION`).
- Mirrors rebuilt in `$TMPDIR` with A3's OWN builders, reused UNCHANGED:
  `tool/eval/apply_delta.py` (A4-frozen) + `tool/runs/make_mirror.py`; swept
  after digest comparison (probe scratch law). No device/model runs.

## Digests (recorded vs rebuilt)

| artifact | scope | recorded (A3) | rebuilt (WS-1) | match |
|---|---|---|---|---|
| plant mirror M | `mirror_shard_sha256` | `22e52d07164ca45f379ccb7ddc42e52a39ec719f73e3d043a3551baa931f02e7` | same | BIT-IDENTICAL |
| removal R, L15 | `post_repair_tensor_f32_sha256` | `7146eb82cfcef9cabb5b72d48bf8aed583f2c9d07ecbf9d3dfe4bbfb317c891a` | same | BIT-IDENTICAL |
| removal R, L19 | `post_repair_tensor_f32_sha256` | `b5f47a9d64b001d7457238beb209484cb836c92968557b6296f23c97fa2509ca` | same | BIT-IDENTICAL |

A3's repair stage was in-memory (`model_on_disk_untouched: true`), so the
per-tensor post-repair f32 digests in `repair_receipt.json` ARE the recorded R
commitments; the rebuilt R store sha
(`fadd55fa38e846d8f1192551e28637c82a843f4fdae26ddfacf78d7df1402953`) is
recorded observed-only.

Patch digests (canonicalJson of `{tensor, columns, direction, scale}`):
L15 `f342d399fbcd58f75a0d9cbdc2a729d993a2f04cdc6624bb4534d68b74f41d8e`,
L19 `b1fb1b213127695653b410e8b34588f10a1c8047ddbbdcdd8db3981e1107b6b2`.
Battery digest (join-table `digests.battery_R`, file pinned by
`A3-verdict-final.join_table_sha256`):
`e1b6dc169042a4c85700b4e2191b9ec9f5703b87f1c7f9ead750ad57ca88be64`.
ReplayReceipts: `reproduced: true` for both tensors (patch commitment +
mirror receipt commitments hold).

## Provenance verified before any rebuild

join-table file digest vs A3-verdict-final; arm-002 `mirror_receipt` /
`repair_receipt` / `recovered.json` / `repair_spec.json` file digests vs the
recorded per-arm digests; base snapshot shard digest
(`bfe05e58…`, read-only, BASE_MUTATED guarded by the builder); truth spec
digests == recorded `sidecar_receipt_spec_digest` == blind arm spec copies;
repair directions == `recovered.json` layers exactly; repair columns == plant
columns; repair scale == −(plant scale).

## Named observations (non-claims)

- `BUILDER_DIGEST_NOTE`: A3-run.jsonl seq0 `tools_sha256` records
  `make_mirror.py = 1f71892e…`, current file is `271c1f04…`. The run-plan row
  predates the pre-plant instrument fix window (seq1 `fix_note`: fixed BEFORE
  any pilot/plant mirror existed; first pilot `make_mirror` stage exit=0).
  Operational equality proof: the current, UNCHANGED builder reproduces the
  recorded mirror digests bit-identically (above). `apply_delta.py` matches
  its A4-frozen digest exactly.
- Driver shakedown: a first scratch-ledger smoke run refused NAMED
  `SHAPE_MISMATCH` (exported a column SLICE while the typed patch carries
  ABSOLUTE column bounds); fixed by exporting the full tensor, before any
  durable row was written. Scratch ledger swept; no durable denominator
  impact.
- Falsifier law held ready: any digest mismatch appends a `ws1-refusal` row
  with NAMED `REPLAY_DIGEST_DRIFT` (both digests) and STOPS — never fudged.
  Fixture-level pin: `test/ws1_live_replay_test.dart`.

Rerun route:

```
dart run tool/runs/ws1_replay.dart \
  --arm-dir "$TMPDIR/wm-a3/blind/arm-002" \
  --base <qwen0.6B-bf16 snapshot> \
  --work "$TMPDIR/wm-ws1" \
  --python ~/.local/share/wm-mlx/bin/python \
  --repo pkgs/xsoulspace_inference_weightmap
```
