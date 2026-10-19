"""Generate the Rust RUNG-0 MODEL parity fixture (cross-language oracle).

tool/nursery/model_def.py defines and runs the model HERE; the checkpoint
is packed through the real pack_at_birth pipeline; the Rust runtime
(native/mlx_native/src/nursery_model.rs) must reproduce the decisions from
the packed store ALONE:

  - per-position, per-layer top-k expert sets  — EXACT (integers; the
    PORTING-MOE.md point: parity fixtures pin routes, not just logits);
  - greedy-decoded bytes and stop reason       — EXACT;
  - final label-head and lm-head logits        — under a stated absolute
    tolerance (Python MLX and mlx-c are different builds of the same
    kernels; the tolerance is pinned beside the numbers, and the margins
    that protect the EXACT pins are pinned too).

Margin law (the block-47 lesson, applied to the fixture itself): the
generator searches seeds until the fixed prompt's router top-1/top-2 gaps
AND every decode-step argmax gap are >= MIN_GAP, so no pinned decision can
flip on cross-build float noise. If no seed qualifies in 50 tries the
generator FAILS rather than pinning an uncomfortable fixture.

Run: ~/.venvs/mlx-ref/bin/python tool/nursery/model_fixture.py
(needs mlx, numpy, safetensors; writes testdata/nursery_model/)
"""

import hashlib
import json
import os
import platform
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import model_def  # noqa: E402
import pack_at_birth  # noqa: E402

PKG_ROOT = os.path.dirname(os.path.dirname(HERE))
TESTDATA = os.path.join(PKG_ROOT, "native", "mlx_native", "testdata", "nursery_model")

H, L, E, K, F = 16, 2, 4, 2, 32
PROMPT = list(b"the nursery sleeps")
MAX_NEW = 8
# Comfort laws (PORTING-MOE.md, applied to the fixture): a pinned decision
# must sit far above cross-build float noise (~1e-3 on logits). Routes are
# integer pins -> strict gap; the byte-level argmax at init is near-uniform
# over 258 logits, so its gap law is looser but still ~20x the noise.
MIN_ROUTE_GAP = 0.1
MIN_ARGMAX_GAP = 0.02
LOGITS_ABS_TOL = 2e-2   # cross-build (python mlx vs mlx-c) absolute tolerance
LABEL_ABS_TOL = 5e-3


def sorted_two(vals):
    s = sorted(vals, reverse=True)
    return s[0], s[1]


def gaps_for(params, cfg, tokens):
    """(min router gap over layers/positions, per-row routes) for one
    forward — the comfort check that makes routes pinnable."""
    out = model_def.forward_sequence(params, cfg, tokens)
    min_gap = float("inf")
    for l in range(cfg.layers):
        for row in out["router_logits"][l].tolist():
            top1, top2 = sorted_two(row)
            min_gap = min(min_gap, top1 - top2)
    return min_gap, out


def greedy(params, cfg, prompt, max_new):
    """Recompute-from-scratch greedy decode — semantically identical to the
    Rust stepwise loop (the recurrence is causal). Returns (emitted,
    stop_reason, min argmax gap)."""
    import mlx.core as mx

    tokens = [model_def.BOS] + list(prompt)
    emitted = []
    stop_reason = "max_new"
    min_argmax_gap = float("inf")
    for _ in range(max_new):
        out = model_def.forward_sequence(params, cfg, tokens)
        logits = [float(v) for v in out["lm_logits"][-1]]
        top1, top2 = sorted_two(logits)
        min_argmax_gap = min(min_argmax_gap, top1 - top2)
        nxt = max(range(len(logits)), key=lambda i: (logits[i], -i))
        if nxt == model_def.EOS:
            stop_reason = "eos"
            break
        emitted.append(nxt)
        tokens.append(nxt)
    return emitted, stop_reason, min_argmax_gap


def main() -> int:
    import mlx
    import numpy as np

    ckpt_dir = os.path.join(TESTDATA, "source_ckpt")
    store_dir = os.path.join(TESTDATA, "store")

    ROUTER_SCALE = 4.0

    def fixture_params(cfg):
        """Init plus a x4 router scale: raw-init router top-2 gaps measure
        ~0.005–0.05, below the strict pin law; a margin-boosted router is
        the PORTING-MOE posture (noise-stable routes), so the fixture ships
        with that headroom baked in."""
        params = model_def.init_params(cfg)
        for l in range(cfg.layers):
            name = f"model.layers.{l}.mlp.gate.weight"
            params[name] = params[name] * ROUTER_SCALE
        return params

    chosen = None
    for seed in range(50):
        cfg = model_def.NurseryConfig(
            hidden_size=H, layers=L, experts=E, topk=K, intermediate=F,
            seed=seed)
        params = fixture_params(cfg)
        tokens = [model_def.BOS] + PROMPT
        router_gap, _ = gaps_for(params, cfg, tokens)
        if router_gap < MIN_ROUTE_GAP:
            continue
        emitted, stop_reason, argmax_gap = greedy(params, cfg, PROMPT, MAX_NEW)
        if argmax_gap < MIN_ARGMAX_GAP or not emitted:
            continue
        chosen = (cfg, params, router_gap, argmax_gap, emitted, stop_reason)
        break
    if chosen is None:
        raise SystemExit(
            f"no seed in 50 gives router gaps >= {MIN_ROUTE_GAP} and argmax "
            f"gaps >= {MIN_ARGMAX_GAP} — refusing to pin an uncomfortable "
            "fixture (PORTING-MOE.md)")
    cfg, params, router_gap, argmax_gap, emitted, stop_reason = chosen
    print(f"seed {cfg.seed}: min router gap {router_gap:.3f}, "
          f"min argmax gap {argmax_gap:.3f}, emitted {len(emitted)} bytes "
          f"(stop: {stop_reason})")

    # The oracle: ONE final forward over the complete token sequence. The
    # recurrence is causal, so routes at position t are what any stepwise
    # runtime saw at t.
    final_tokens = [model_def.BOS] + PROMPT + emitted
    out = model_def.forward_sequence(params, cfg, final_tokens)
    routes = [out["routes"][l] for l in range(cfg.layers)]   # per layer, [T][k]
    routes_by_pos = [[[] for _ in range(cfg.layers)]
                     for _ in final_tokens]
    for l in range(cfg.layers):
        for pos, sel in enumerate(routes[l]):
            routes_by_pos[pos][l] = sel
    label_logits = [float(v) for v in out["label_logits"]]
    final_logits = [float(v) for v in out["lm_logits"][-1]]

    model_def.save_checkpoint(params, cfg, ckpt_dir)
    manifest, stats = pack_at_birth.pack_checkpoint(ckpt_dir, store_dir)
    manifest_before = open(os.path.join(store_dir, "manifest.json"), "rb").read()
    pack_at_birth.pack_checkpoint(ckpt_dir, store_dir)
    manifest_after = open(os.path.join(store_dir, "manifest.json"), "rb").read()
    assert manifest_before == manifest_after, "repack was not a no-op"
    assert stats["router_dtypes"] == ["float32"], \
        f"router must be fp32, got {stats['router_dtypes']}"

    expectations = {
        "contract": pack_at_birth.CONTRACT,
        "generator": "tool/nursery/model_fixture.py",
        "command": " ".join(["~/.venvs/mlx-ref/bin/python"] + sys.argv),
        "generated_utc": subprocess.run(
            ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True,
            text=True).stdout.strip(),
        "provenance": {
            "python": platform.python_version(),
            "numpy": np.__version__,
            "mlx": getattr(mlx, "__version__", "unknown"),
            "platform": platform.platform(),
        },
        "config": cfg.to_json(),
        "prompt": PROMPT,
        "max_new": MAX_NEW,
        "bos": model_def.BOS,
        "eos": model_def.EOS,
        "margins": {"min_router_gap": round(router_gap, 4),
                    "min_argmax_gap": round(argmax_gap, 4),
                    "min_route_gap_law": MIN_ROUTE_GAP,
                    "min_argmax_gap_law": MIN_ARGMAX_GAP},
        "tolerances": {"logits_abs_tol": LOGITS_ABS_TOL,
                       "label_abs_tol": LABEL_ABS_TOL},
        "routes_by_pos": routes_by_pos,
        "emitted": emitted,
        "stop_reason": stop_reason,
        "label_logits": label_logits,
        "final_logits": final_logits,
        "manifest_sha256": hashlib.sha256(manifest_after).hexdigest(),
        "segments": len(manifest["segments"]),
    }
    os.makedirs(TESTDATA, exist_ok=True)
    out_path = os.path.join(TESTDATA, "expectations.json")
    with open(out_path, "w") as fh:
        json.dump(expectations, fh, indent=2, sort_keys=True)

    print(f"checkpoint: {ckpt_dir}")
    print(f"store:      {store_dir} ({len(manifest['segments'])} segments, "
          f"{stats['total_bytes']} bytes)")
    print(f"expectations: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
