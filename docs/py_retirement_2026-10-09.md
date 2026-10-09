# Python retirement — the local text-model production line (2026-10-09)

Directive: the native in-process engines become the ONLY serving/benchmark
line; python (`mlx_lm`, the `~/.venvs/mlx-ref` venv) is retired to exactly
two roles — (a) benchmark REFERENCE legs and (b) golden/fixture recording.
This is the execution audit of ADR 0056 item 1 ("the mlx_local runtime
swap"); ADR 0057 (in flight, separate session) owns the wider engine-host
refactor.

## The python-role table (audited 2026-10-09, both repos)

| Where | Role before | Role now | Evidence / action |
|---|---|---|---|
| harness `xsoulspace_agentic_afm/lib/src/mlx_binding.dart` | serving — attach-only by default at `http://127.0.0.1:8765`; `HARNESS_MLX_SPAWN=1` opt-in spawned python by default | serving — unchanged behavior (attach-only); docs flipped native-first; `HARNESS_MLX_SPAWN=1` stays as the documented escape hatch, its unset-executable fallback labeled "retired python reference server" | doc edit (this audit) |
| harness `xsoulspace_optmem/bin/optmem_nap_draft.dart` | serving — attach-only; the not-ready error message told users to start `mlx_lm.server` | serving — error message now names the native server (`mlx_serve_native`) as the bring-up | doc/message edit (this audit) |
| harness `xsoulspace_optmem/tool/nap_draft_benchmark.dart` | benchmark — attach mode default; spawn-mode example pointed at `<venv>/bin/mlx_lm.server` | benchmark — attach mode labeled THE production line (native server); spawn mode relabeled `py-reference` leg, "never a production row" | doc edit (this audit) |
| monorepo `pkgs/xsoulspace_inference_mlx/tool/napbench_text_lane.dart` | benchmark — already measured ONLY the in-process native engine (`NativeMlxTextEngine`); no python leg, no server leg | unchanged + native-line confirmation added to the header; acceptance verdicts (TTFT@4k ≤300 ms, LFM2.5 decode ≥45 tok/s) untouched | verified by full read; header edit (this audit) |
| monorepo `pkgs/xsoulspace_inference_mlx/lib/src/mlx_serve_runtime.dart` | serving escape hatch — `executable` defaults to `mlx_lm.server`, reachable ONLY behind an explicit `spawnOnMiss: true` | unchanged (mlx package lib/ under concurrent WIP by another session); attach-only remains the default everywhere, so python never spawns by default | noted; owner flips when convenient |
| monorepo `pkgs/xsoulspace_inference_mlx/bin/mlx_serve_native.dart` | serving — NATIVE (the `mlx_text_native` dylib behind the OpenAI-compatible loopback wire) | none — this IS the native line | no change |
| monorepo `pkgs/xsoulspace_inference_local_serve/README.md` | docs — described the mlx consumer as `mlx_lm.server` on loopback | docs — native engine via `mlx_serve_native.dart`; python = retired reference | doc edit (this audit) |
| monorepo `pkgs/xsoulspace_inference_mlx/README.md`, `CHANGELOG.md`, `hook/*` | (concurrent WIP of the mlx session — already frames python as "(fallback)") | untouched by this audit | hard boundary |
| monorepo `pkgs/xsoulspace_inference_laya/tool/gen_qwen3_parity_fixture.py`, `tool/py_decode_scaling.py` | golden/fixture recording + decode-scaling reference | KEPT — exactly the retired roles; laya lane owned elsewhere | no change |
| monorepo `docs/decisions/0054`, `0055` | python reference venv for kernel parity/traces | KEPT — reference role | no change |
| crontab, LaunchAgents, harness lane specs | nothing found spawning python serve | — | `crontab -l` grep empty; `~/Library/LaunchAgents` empty; no `CommandLaneSpec` touches mlx |

Net: NOTHING in either repo spawns python for serving by default — every
lane is attach-only; python is reachable only through the explicit
`*_MLX_SPAWN=1` escape hatches, which the retirement law allows to stay.

## What flipped (this audit's diffs)

Monorepo:
- `pkgs/xsoulspace_inference_mlx/tool/napbench_text_lane.dart` — header:
  native-line confirmation (native-only measurement; python relegated to
  reference legs + goldens).
- `pkgs/xsoulspace_inference_local_serve/README.md` — consumer line now
  names the native server as the serve shape.
- `docs/py_retirement_2026-10-09.md` — this file.

Harness (separate commit, `feat(afm):`):
- `pkgs/xsoulspace_agentic_afm/lib/src/mlx_binding.dart` — serving-line
  doc flipped native-first; spawn knob documented as escape hatch with the
  python fallback labeled retired. No behavior change (attach-only default
  preserved; `mlx_binding_test` still passes).
- `pkgs/xsoulspace_optmem/bin/optmem_nap_draft.dart` — not-ready message
  now names the native server bring-up instead of `mlx_lm.server`.
- `pkgs/xsoulspace_optmem/tool/nap_draft_benchmark.dart` — attach mode
  documented as the production line; spawn mode relabeled the
  `py-reference` leg.

## Live proof of the python-free line (2026-10-09, this machine)

Throwaway script (in-process `NativeMlxChatEndpoint` →
`MlxChatWireServer` on an ephemeral loopback port → `MlxLocalTextClient`
with `MlxServeRuntime(spawnOnMiss: false)` → one real `infer`):

- model: `mlx-community/Qwen3-0.6B-4bit` (cached HF snapshot `73e3e38d`,
  never downloaded)
- native engine load: 2594 ms (cold first load in a fresh shell; the
  warm ADR-table number is 0.16 s)
- attach + health: `true` in 97 ms (attach-only — nothing external launched)
- one completion: 535 ms wall, 27 prompt tokens / 11 completion tokens,
  `finish_reason: stop`, output: "The largest planet in the solar system
  is Jupiter."
- `pgrep -f mlx_lm` during the run: NONE
- serving path: native dylib in-process → pure-Dart loopback wire →
  client. No python, no spawned process, no egress.

## Gates (one line each)

- napbench smoke: `dart run pkgs/xsoulspace_inference_mlx/tool/napbench_text_lane.dart --models qwen06 --runs 2 --prefill 2000 --decode-tokens 16` →
  `load 3870ms, RSS 450→450 MB; prefill ~2000tok (actual 1409): 2912ms engine / 3263ms wall; decode p50 28.0 tok/s` — native line, runs green.
  (2-run/16-token smoke numbers are not acceptance rows; verdicts only
  fire at ≥3800 prompt tokens and for LFM2.5, by design.)
- afm: `dart analyze lib/src/mlx_binding.dart` → No issues found;
  `dart test test/mlx_binding_test.dart` → All tests passed.
- optmem: `dart analyze bin/optmem_nap_draft.dart tool/nap_draft_benchmark.dart` →
  No issues found.
- monorepo: `dart analyze pkgs/xsoulspace_inference_mlx/tool/napbench_text_lane.dart` →
  No issues found.
- PRE-EXISTING BREAK (not from this audit, named for its owner):
  `xsoulspace_optmem test/nap_draft_lane_test.dart` fails at `setUpAll` —
  the test compiles `bin/optmem_nap_draft.dart` with `dart compile`, which
  does not support build hooks; the mlx package gained its native-assets
  hook on 2026-10-08, so any `dart compile` of that bin now dies at the
  tool level regardless of source content. Owner: the mlx hook work (hook
  files are that session's WIP). Rerun route: after the hook session
  lands, either the test moves to `dart build`/`dart run` harnessing or
  the lane gets a named skip.

## Machine-state note (paid for here, useful to the next agent)

The mlx hook's `swift build` failed twice today with the Xcode-build-system
tree (`.build/out/`) holding an on-disk build description whose Metal
toolchain path pointed at a dead cryptex suffix
(`...MetalToolchain-v27.1.266.1.rS1xSh/...` — Xcode 27 rotates the cryptex
mount). Removing the derived `native/mlx_text_native/.build/out/` tree and
the cached failed hook run under `.dart_tool/hooks_runner/` let the hook
rebuild cleanly (66 s incremental); a direct `swift build -c release`
re-provisioned the toolchain. Pure derived-state recovery; no source or
WIP files touched.

## Non-claims

- NOT claimed: the harness palette's `mlx_local` runtime itself was
  swapped to compose the engine in-process — the wire-level swap is what
  is proven (native server behind the same `/health` +
  `/v1/chat/completions`); the fully in-process composition (no loopback
  hop) remains ADR 0057 territory.
- NOT claimed: python is absent from the machine or from all lanes — it is
  absent from every DEFAULT serving path; the `*_MLX_SPAWN=1` escape
  hatches still fall back to `mlx_lm.server` when explicitly opted into
  and not overridden.
- NOT claimed: napbench acceptance rows were re-met today — the smoke ran
  2 runs / 16 decode tokens deliberately; the oracles are unchanged and
  remain owned by the nightly.
- NOT claimed: `mlx_serve_native` accepts the spawn-knob argument shape —
  it rejects `--host`, so `MlxServeArguments.command` cannot target it
  today; that flip belongs to the mlx package owner.
- NOT claimed: the laya lane was audited or modified — its python tools
  are kept reference/golden roles and its bench lane is owned elsewhere.
- NOT edited: every file in the other session's WIP set (mlx CHANGELOG/
  README/hook/test; harness SKILL.md, docs/evidence/*, ROADMAP.md,
  harnessd.jit.dill) — verified untouched and unstaged.
