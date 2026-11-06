#!/usr/bin/env python3
"""wm_qwen35_bench.py — Qwen3.5 tokens/s bench (serial, mlx-lm venv).

Serial house law: prompts run one after another, single stream, no
batching (the batched lane is L-G4's native gate, not this script's).

Convention note (mlx-lm's own counters): `prompt_tps` is measured to the
FIRST generated token, so prefill time includes the first decode step;
`generation_tps` covers all generated tokens from that point. Aggregates:
  prefill_tok_s = sum(prompt_tokens) / sum(prompt_tokens / prompt_tps)
  decode_tok_s  = sum(generation_tokens) / sum(generation_tokens / generation_tps)
  wall_ms       = wall clock of the whole serial generation phase
                  (model load excluded; load_ms reported separately)
Per house law (POWER.md) absolute ms on this box are non-claims until
recorded with power state; ratios are the measurement. eos_stop: true
(stream_generate default) — a prompt that stops early contributes its real
counts, visible per prompt in the "per_prompt" rows.

Args:
  --model DIR        checkpoint dir
  --prompt-count K   number of synthetic prompts (>= 1), cycled from a fixed
                     deterministic list (seeded corpus, no randomness)
  --max-tokens N     tokens per prompt (>= 1)
  --out JSON         {prefill_tok_s, decode_tok_s, wall_ms} at top level,
                     plus "per_prompt" rows and "provenance"
  --dry-run          print the plan JSON (mlx NOT imported) and exit 0

Exit codes (NAMED refusals "CODE: message" on stderr, never silent):
  0 OK; 1 INTERNAL; 2 refusal: MODEL_DIR_MISSING, CONFIG_MISSING,
  CONFIG_UNPARSEABLE, ARCH_UNSUPPORTED, PROMPT_COUNT_INVALID,
  MAX_TOKENS_INVALID, MLX_UNAVAILABLE, BENCH_COUNTERS_MISSING,
  OUT_WRITE_FAILED

The validation block is mirrored verbatim in wm_qwen35_generate.py and
wm_qwen35_digest.py (scope law: the three boundary scripts stay standalone).

Run via the venv resolver:
  WM_PY=$(tool/nursery/wm_pyenv.sh) && "$WM_PY" tool/nursery/wm_qwen35_bench.py ...
"""

import argparse
import json
import os
import sys
import time

SUPPORTED_MODEL_TYPES = ("qwen3_5",)

# Fixed deterministic bench corpus (cycled to --prompt-count). Synthetic,
# no private data; same spirit as the parity fixture's synthetic prompt.
BENCH_PROMPTS = (
    "The history of computing begins with",
    "A careful engineer would first verify that",
    "In a memory-bound transformer decode loop,",
    "The simplest way to explain gravity is",
    "When porting a model loader to Rust,",
    "A quiet morning in the mountains feels",
    "The second law of thermodynamics states that",
    "To benchmark a GPU fairly, one must",
)


def refuse(code, message):
    print(f"{code}: {message}", file=sys.stderr)
    raise SystemExit(2)


def read_arch(model_dir):
    """Return (model_type, architectures) from the checkpoint config.json,
    refusing with a NAMED code when the dir/config/arch is wrong."""
    if not os.path.isdir(model_dir):
        refuse("MODEL_DIR_MISSING", f"model dir not found: {model_dir}")
    cfg_path = os.path.join(model_dir, "config.json")
    if not os.path.isfile(cfg_path):
        refuse("CONFIG_MISSING", f"config.json not found in: {model_dir}")
    try:
        with open(cfg_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        refuse("CONFIG_UNPARSEABLE", f"{cfg_path}: {e}")
    model_type = cfg.get("model_type")
    architectures = cfg.get("architectures") or []
    if model_type not in SUPPORTED_MODEL_TYPES:
        text_mt = (cfg.get("text_config") or {}).get("model_type")
        refuse(
            "ARCH_UNSUPPORTED",
            f"model_type={model_type!r} (architectures={architectures}, "
            f"text_config.model_type={text_mt!r}); supported: "
            f"{list(SUPPORTED_MODEL_TYPES)}",
        )
    return model_type, architectures


def parse_args(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompt-count", required=True, type=int)
    ap.add_argument("--max-tokens", required=True, type=int)
    ap.add_argument("--out", required=True)
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    if args.prompt_count < 1:
        refuse("PROMPT_COUNT_INVALID", f"--prompt-count must be >= 1, got {args.prompt_count}")
    if args.max_tokens < 1:
        refuse("MAX_TOKENS_INVALID", f"--max-tokens must be >= 1, got {args.max_tokens}")
    model_type, architectures = read_arch(args.model)
    prompts = [BENCH_PROMPTS[i % len(BENCH_PROMPTS)] for i in range(args.prompt_count)]

    if args.dry_run:
        plan = {
            "script": "wm_qwen35_bench.py",
            "model": os.path.abspath(args.model),
            "arch": model_type,
            "architectures": architectures,
            "prompt_count": len(prompts),
            "max_tokens": args.max_tokens,
            "out": os.path.abspath(args.out),
            "mlx_imported": False,
        }
        print(json.dumps(plan))
        return 0

    # Runtime imports (PYTHON-BOUNDARY idiom).
    try:
        import importlib.metadata as importlib_metadata

        import mlx.core as mx
        from mlx_lm import load, stream_generate
        from mlx_lm.sample_utils import make_sampler
    except ImportError as e:
        refuse("MLX_UNAVAILABLE", f"mlx/mlx_lm import failed: {e}")

    sampler = make_sampler(temp=0.0)
    t_load0 = time.perf_counter()
    model, tokenizer = load(args.model)
    load_ms = (time.perf_counter() - t_load0) * 1000.0

    per_prompt = []
    t0 = time.perf_counter()
    for prompt_id, prompt in enumerate(prompts):
        final = None
        for resp in stream_generate(
            model, tokenizer, prompt, max_tokens=args.max_tokens, sampler=sampler
        ):
            int(resp.token)  # MLX IS LAZY: force the actual output every step
            final = resp
        if (
            final is None
            or final.prompt_tps <= 0.0
            or final.generation_tps <= 0.0
            or final.generation_tokens < 1
        ):
            refuse(
                "BENCH_COUNTERS_MISSING",
                f"prompt {prompt_id}: mlx-lm counters unusable "
                f"(final={final is not None})",
            )
        per_prompt.append(
            {
                "prompt_id": prompt_id,
                "prompt": prompt,
                "prompt_tokens": int(final.prompt_tokens),
                "prompt_tps": float(final.prompt_tps),
                "generation_tokens": int(final.generation_tokens),
                "generation_tps": float(final.generation_tps),
                "finish_reason": final.finish_reason,
                "peak_memory_gb": float(final.peak_memory),
            }
        )
    wall_ms = (time.perf_counter() - t0) * 1000.0

    sum_prompt_tokens = sum(r["prompt_tokens"] for r in per_prompt)
    sum_gen_tokens = sum(r["generation_tokens"] for r in per_prompt)
    sum_prefill_s = sum(r["prompt_tokens"] / r["prompt_tps"] for r in per_prompt)
    sum_decode_s = sum(r["generation_tokens"] / r["generation_tps"] for r in per_prompt)

    out_obj = {
        "prefill_tok_s": round(sum_prompt_tokens / sum_prefill_s, 3),
        "decode_tok_s": round(sum_gen_tokens / sum_decode_s, 3),
        "wall_ms": round(wall_ms, 3),
        "per_prompt": per_prompt,
        "provenance": {
            "script": "wm_qwen35_bench.py",
            "model_dir": os.path.abspath(args.model),
            "model_type": model_type,
            "architectures": architectures,
            "mlx_version": importlib_metadata.version("mlx"),
            "mlx_lm_version": importlib_metadata.version("mlx-lm"),
            "python_version": sys.version.split()[0],
            "prompt_count": args.prompt_count,
            "max_tokens": args.max_tokens,
            "sampler": "greedy (temp=0.0)",
            "eos_stop": True,
            "serial": True,
            "load_ms": round(load_ms, 3),
            "tps_convention": (
                "mlx-lm counters: prompt_tps measured to the first generated "
                "token (prefill includes the first decode step); "
                "generation_tps covers all generated tokens from that point"
            ),
            "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        },
    }
    try:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        os.makedirs(out_dir, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(out_obj, f, ensure_ascii=False, indent=2)
            f.write("\n")
    except OSError as e:
        refuse("OUT_WRITE_FAILED", f"{args.out}: {e}")

    print(
        f"prefill {out_obj['prefill_tok_s']} tok/s | decode "
        f"{out_obj['decode_tok_s']} tok/s | wall {out_obj['wall_ms']} ms "
        f"-> {args.out}"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception:
        import traceback

        traceback.print_exc()
        print("INTERNAL: unexpected exception (traceback above)", file=sys.stderr)
        raise SystemExit(1)
