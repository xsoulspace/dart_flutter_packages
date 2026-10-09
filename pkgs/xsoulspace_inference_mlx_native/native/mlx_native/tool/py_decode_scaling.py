"""ADR 0055 P1 python reference leg: per-token decode wall time at the same
context lengths as the Rust sweep (src/bin/qwen_decode_bench), with the same
chunked-prefill shape mlx_lm's generate_step uses (2048-token prefill chunks,
last token through the decode loop).

Usage: python py_decode_scaling.py [model_path] [ctx_len] [steps]
"""

import json
import pathlib
import sys
import time

import mlx.core as mx
from mlx_lm import load
from mlx_lm.models import cache as lm_cache

FIXTURE = pathlib.Path(
    "/Users/antonio/xs/storage_problem/dart_flutter_packages/pkgs/"
    "xsoulspace_inference_mlx_native/native/mlx_native/testdata/qwen3_06b_parity.json"
)

model_path = None
args = [a for a in sys.argv[1:]]
if args and not args[0].isdigit():
    model_path = args.pop(0)
if model_path is None:
    import glob
    import os
    cands = glob.glob(os.path.expanduser(
        "~/.cache/huggingface/hub/*Qwen3-0.6B-4bit/snapshots/*/"))
    assert cands, "snapshot missing"
    model_path = cands[0]

ctx_len = int(args[0]) if args else 2048
steps = int(args[1]) if len(args) > 1 else 16

model, tok = load(model_path)
fixture = json.loads(FIXTURE.read_text())
base = fixture["prompt_ids"]
ids = (base * (ctx_len // len(base) + 1))[:ctx_len]

cache = lm_cache.make_prompt_cache(model)
PREFILL = 2048
rest = list(ids)
t0 = time.perf_counter()
while len(rest) > 1:
    n = min(PREFILL, len(rest) - 1)
    logits = model(mx.array([rest[:n]]), cache=cache)
    mx.eval(logits)
    rest = rest[n:]
# The last prompt token rides the decode loop (parity-load-bearing shape).
logits = model(mx.array([rest]), cache=cache)
mx.eval(logits)
print(f"python prefill {ctx_len}: {time.perf_counter()-t0:.2f}s", file=sys.stderr)

samples = []
next_tok = rest[-1]
for _ in range(steps):
    t0 = time.perf_counter()
    logits = model(mx.array([[next_tok]]), cache=cache)
    nx = mx.argmax(logits[:, -1, :], axis=-1)
    mx.eval(nx)
    tok_id = int(nx.item())
    samples.append((time.perf_counter() - t0) * 1e3)
    next_tok = tok_id
samples.sort()
n = len(samples)
print(f"python decode ctx={ctx_len} n={n} p50={samples[n//2]:.2f}ms "
      f"p90={samples[int(n*0.9)]:.2f}ms")
