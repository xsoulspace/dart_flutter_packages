"""MTP HEAD PARITY FIXTURE — the native Rust port's oracle (MTP-GATES J-G4).

WHY THIS FILE EXISTS. The native Rust MTP port
(`native/mlx_native/src/qwen_mtp.rs`) must reproduce the Python reference's
draft head op for op. The law this package follows is "Every new
architecture = Rust port with a parity fixture (venv-recorded, provenance in
the file). Never weaken an oracle" (AGENTS.md).

WHAT THE FIXTURE PINS. One synthetic trunk (NO checkpoint: the head is a
pure function of its five weights and two input vectors, so the fixture is
runnable without the model):

  * the head's five weights, per depth, in the EXPORTER's tensor names
    (`model.mtp.d{j}.{proj,norm,gate,up,down}.weight`, F32) — the exact
    names the Rust loader reads;
  * the tied embedding matrix (`model.embed_tokens.weight`, F32) — the head's
    token rows and the tied vocab projection (`as_linear`);
  * the head forward's OUTPUT hidden, per depth;
  * the projected logits and the argmax token, per depth;
  * the CHAINED depth-1 output (head 1 reads head 0's hidden and the
    embedding of head 0's proposed token) — the chain is the "MTP count" and
    it is pinned, not assumed.

The head weights come from the reference's own `init_head(H, F, seed)` and
the forward from the reference's own `head_forward` — the Rust port mirrors
THOSE functions, not a re-derivation of them.

PROVENANCE is recorded inside the fixture (generator path + sha256, command,
mlx version, tolerances) so the oracle's provenance is auditable from the
fixture alone.

Usage:
  ~/.venvs/mlx-ref/bin/python tool/nursery/mtp_head_fixture.py \
      --out native/mlx_native/testdata/qwen_mtp_head_synth.safetensors \
      --json native/mlx_native/testdata/qwen_mtp_parity.json
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import mlx.core as mx  # noqa: E402
import mtp_retarget  # noqa: E402  (the reference: init_head / head_forward)

# The synthetic trunk's shape. Small on purpose: the fixture is a
# correctness oracle, not a benchmark, and it must be readable.
H = 8
F = 16
V = 32
COUNT = 2  # the MTP count K: two chained heads
HEAD_SEED = 7  # head j uses seed HEAD_SEED + j (the reference's own rule)
EMB_SEED = 101
INPUT_SEED = 202
TOKEN_IDS = [3, 11]

# The tolerances the Rust port is held to. The head forward is a chain of
# matmuls, an rms_norm and elementwise ops on f32; python-mlx and the
# vendored mlx-c are different builds of the same kernels, so the comparison
# is a tolerance, not bit-identity (the same stance as the nursery model
# parity fixture). The margins are generous against the observed spread and
# are stated HERE, before the Rust run, so they cannot be a knob.
TOLERANCES = {
    "hidden_abs_tol": 1e-4,
    "logits_abs_tol": 1e-3,
    "embedding_abs_tol": 1e-6,
}


def sha256_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def f32_list(a):
    """Row-major f32 list of a numpy/mx array."""
    return [float(x) for x in mx.array(a).reshape([-1]).tolist()]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", required=True, help="the synthetic safetensors file")
    ap.add_argument("--json", required=True, help="the parity fixture (JSON)")
    args = ap.parse_args(argv)

    # ---- the synthetic tied embedding (the head's rows + the projection) ----
    mx.random.seed(EMB_SEED)
    emb = (mx.random.normal([V, H]) * (1.0 / H**0.5)).astype(mx.float32)

    # ---- the head chain (the reference's own init) ----
    heads = [mtp_retarget.init_head(H, F, seed=HEAD_SEED + j) for j in range(COUNT)]
    keys = ["proj", "norm", "gate", "up", "down"]

    # ---- the inputs ----
    mx.random.seed(INPUT_SEED)
    prev_hidden = mx.random.normal([1, 1, H]).astype(mx.float32)
    token_ids = list(TOKEN_IDS)

    # ---- the forward: depth 0, then the chain's depth 1 ----
    expectations = []
    prev = prev_hidden
    token = token_ids[0]
    for j in range(COUNT):
        token_emb = emb[token].astype(mx.float32)[None, None, :]
        h = mtp_retarget.head_forward(heads[j], prev, token_emb)
        # The tied vocab projection: the reference's `as_linear` on a plain
        # (f32) embedding is a plain matmul against the transposed weight.
        logits = h @ emb.T
        am = mx.argmax(logits[0], axis=-1)
        mx.eval(h, logits, am)
        expectations.append(
            {
                "depth": j,
                "input_token": int(token),
                "hidden": f32_list(h),
                "logits": f32_list(logits),
                "argmax": int(am.item()),
            }
        )
        # The chain: head j+1 reads head j's hidden and the embedding of head
        # j's PROPOSED token (the reference's `prev = dh_self`,
        # `emb_self = emb_w[prev_argmax]`).
        prev = h
        token = int(am.item())

    # ---- the safetensors file: the exporter's names + the embedding ----
    tensors = {}
    for j in range(COUNT):
        for k in keys:
            tensors[f"model.mtp.d{j}.{k}.weight"] = heads[j][k].astype(mx.float32)
    tensors["model.embed_tokens.weight"] = emb
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    mx.save_safetensors(args.out, tensors)

    # ---- the fixture ----
    fixture = {
        "provenance": {
            "generator_source": "tool/nursery/mtp_head_fixture.py",
            "generator_sha256": sha256_file(os.path.abspath(__file__)),
            "command": "~/.venvs/mlx-ref/bin/python tool/nursery/mtp_head_fixture.py",
            "mlx_version": mx.__version__,
            "model": "synthetic — no checkpoint; the head is a pure function of "
            "its five weights and two input vectors",
            "oracle": "Python MLX mtp_retarget.init_head + mtp_retarget.head_forward "
            "+ the tied embedding projection; generated BEFORE the Rust parity run",
            "when_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        },
        "config": {
            "hidden_size": H,
            "mlp_width": F,
            "vocab": V,
            "count": COUNT,
            "head_seed": HEAD_SEED,
            "embedding_seed": EMB_SEED,
            "input_seed": INPUT_SEED,
            "rms_eps": 1e-5,
            "safetensors": os.path.basename(args.out),
            "safetensors_sha256": sha256_file(os.path.abspath(args.out)),
        },
        "inputs": {
            "prev_hidden": f32_list(prev_hidden),
            "token_ids": token_ids,
            "embedding_rows": {
                str(t): f32_list(emb[t]) for t in sorted(set(token_ids))
            },
        },
        "expectations": expectations,
        "tolerances": TOLERANCES,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
    with open(args.json, "w") as fh:
        json.dump(fixture, fh, indent=2, sort_keys=True)
        fh.write("\n")

    print(f"wrote {args.out}")
    print(f"wrote {args.json}")
    for e in expectations:
        print(
            f"  depth {e['depth']}: input_token {e['input_token']} -> argmax "
            f"{e['argmax']}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
