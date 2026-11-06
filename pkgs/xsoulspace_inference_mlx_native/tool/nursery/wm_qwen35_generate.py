#!/usr/bin/env python3
"""wm_qwen35_generate.py — Qwen3.5 (model_type qwen3_5) greedy/cfg generation
boundary script for the mlx-lm venv (PYTHON FIRST half; a Rust loader is
compared against wm_qwen35_digest.py's fixture).

Loads via mlx_lm.load, which handles the sharded safetensors index and the
Qwen3_5ForConditionalGeneration multimodal wrapper (text tower in
text_config; vision weights are dropped by the model's sanitize()).

Args:
  --model DIR        checkpoint dir (config.json + weights, HF-cache snapshot)
  --prompts FILE     one prompt per line; blank lines are skipped
  --max-tokens N     tokens to generate per prompt (>= 1)
  --sampler greedy|<cfg-json>
                     "greedy" (default) = make_sampler(temp=0.0);
                     otherwise a JSON object of make_sampler kwargs, e.g.
                     '{"temp": 0.7, "top_p": 0.9}'
  --out JSONL        output file, one JSON object per prompt:
                     {prompt_id, prompt, output_text, output_tokens,
                      hit_token_limit, finish_reason, wall_ms}
  --dry-run          print the plan as JSON on stdout (model, arch, prompt
                     count, max_tokens, sampler, out, "mlx_imported": false)
                     and exit 0 WITHOUT importing mlx

Exit codes (NAMED refusals on stderr as "CODE: message", never silent):
  0  OK
  1  INTERNAL — unexpected exception (traceback on stderr)
  2  NAMED refusal: MODEL_DIR_MISSING, CONFIG_MISSING, CONFIG_UNPARSEABLE,
     ARCH_UNSUPPORTED (names the model_type found), PROMPTS_MISSING,
     PROMPTS_EMPTY, MAX_TOKENS_INVALID, SAMPLER_CONFIG_INVALID,
     MLX_UNAVAILABLE, OUT_WRITE_FAILED

EOS behaviour: stream_generate default (EOS stop ON) — this is the sanity
generation path, not a parity oracle (parity streams live in
wm_qwen35_digest.py and run EOS OFF per house law).

The validation block below is mirrored verbatim in wm_qwen35_digest.py and
wm_qwen35_bench.py (scope law: the three boundary scripts stay standalone).

Run via the venv resolver:
  WM_PY=$(tool/nursery/wm_pyenv.sh) && "$WM_PY" tool/nursery/wm_qwen35_generate.py ...
"""

import argparse
import json
import os
import sys
import time

# The arch this script accepts. mlx-lm 0.32.x resolves model_type -> module
# mlx_lm.models.<model_type>; "qwen3_5" maps to the hybrid
# linear_attention/full_attention tower (Qwen3_5ForConditionalGeneration
# wrapper or flat text config). Anything else is refused BEFORE importing
# mlx, so the refusal is named even on a machine without the venv.
SUPPORTED_MODEL_TYPES = ("qwen3_5",)

SAMPLER_KEYS = (
    "temp",
    "top_p",
    "min_p",
    "min_tokens_to_keep",
    "top_k",
    "xtc_probability",
    "xtc_threshold",
    "xtc_special_tokens",
)


def refuse(code, message):
    print(f"{code}: {message}", file=sys.stderr)
    raise SystemExit(2)


def read_prompts(path):
    """One prompt per line; blank/whitespace-only lines are skipped."""
    if not os.path.isfile(path):
        refuse("PROMPTS_MISSING", f"prompts file not found: {path}")
    with open(path, "r", encoding="utf-8") as f:
        lines = [ln.rstrip("\n").rstrip("\r") for ln in f]
    prompts = [ln for ln in lines if ln.strip()]
    if not prompts:
        refuse("PROMPTS_EMPTY", f"no non-empty prompt lines in: {path}")
    return prompts


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
    ap.add_argument("--model", required=True, help="checkpoint dir")
    ap.add_argument("--prompts", required=True, help="prompts file, one per line")
    ap.add_argument("--max-tokens", required=True, type=int)
    ap.add_argument("--sampler", default="greedy", help='"greedy" or cfg JSON')
    ap.add_argument("--out", required=True, help="output JSONL path")
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args(argv)


def check_max_tokens(n):
    if n < 1:
        refuse("MAX_TOKENS_INVALID", f"--max-tokens must be >= 1, got {n}")


def validate_sampler_spec(spec):
    """Parse/shape-check the --sampler spec WITHOUT mlx. Returns None for
    "greedy" or the cfg dict; refuses SAMPLER_CONFIG_INVALID otherwise."""
    if spec == "greedy":
        return None
    try:
        cfg = json.loads(spec)
    except json.JSONDecodeError as e:
        refuse("SAMPLER_CONFIG_INVALID", f"--sampler is not valid JSON: {e}")
    if not isinstance(cfg, dict):
        refuse("SAMPLER_CONFIG_INVALID", f"--sampler JSON must be an object, got {type(cfg).__name__}")
    unknown = sorted(set(cfg) - set(SAMPLER_KEYS))
    if unknown:
        refuse("SAMPLER_CONFIG_INVALID", f"unknown sampler keys {unknown}; allowed: {list(SAMPLER_KEYS)}")
    return cfg


def build_sampler(spec, make_sampler):
    cfg = validate_sampler_spec(spec)
    if cfg is None:
        return make_sampler(temp=0.0)
    try:
        return make_sampler(**cfg)
    except (TypeError, ValueError) as e:
        refuse("SAMPLER_CONFIG_INVALID", f"make_sampler rejected config: {e}")


def main(argv):
    args = parse_args(argv)
    check_max_tokens(args.max_tokens)
    prompts = read_prompts(args.prompts)
    model_type, architectures = read_arch(args.model)
    validate_sampler_spec(args.sampler)  # named refusal even on --dry-run

    if args.dry_run:
        plan = {
            "script": "wm_qwen35_generate.py",
            "model": os.path.abspath(args.model),
            "arch": model_type,
            "architectures": architectures,
            "prompt_count": len(prompts),
            "max_tokens": args.max_tokens,
            "sampler": args.sampler,
            "out": os.path.abspath(args.out),
            "mlx_imported": False,
        }
        print(json.dumps(plan))
        return 0

    # Runtime imports (PYTHON-BOUNDARY idiom): mlx is imported only on the
    # real path, so --dry-run and every NAMED refusal above run without it.
    try:
        import mlx.core as mx  # noqa: F401  (forces device init parity)
        from mlx_lm import load, stream_generate
        from mlx_lm.sample_utils import make_sampler
    except ImportError as e:
        refuse("MLX_UNAVAILABLE", f"mlx/mlx_lm import failed: {e}")

    sampler = build_sampler(args.sampler, make_sampler)
    model, tokenizer = load(args.model)

    rows = []
    for prompt_id, prompt in enumerate(prompts):
        pieces = []
        tokens_in_text = 0
        finish_reason = None
        t0 = time.perf_counter()
        for resp in stream_generate(
            model, tokenizer, prompt, max_tokens=args.max_tokens, sampler=sampler
        ):
            int(resp.token)  # MLX IS LAZY: force the actual output every step
            pieces.append(resp.text)
            if resp.finish_reason is None:
                tokens_in_text += 1  # one yielded intermediate == one text token
            else:
                finish_reason = resp.finish_reason
                if finish_reason == "length":
                    tokens_in_text += 1  # final token was added before the break
        wall_ms = (time.perf_counter() - t0) * 1000.0
        rows.append(
            {
                "prompt_id": prompt_id,
                "prompt": prompt,
                "output_text": "".join(pieces),
                "output_tokens": tokens_in_text,
                "hit_token_limit": finish_reason == "length",
                "finish_reason": finish_reason,
                "wall_ms": round(wall_ms, 3),
            }
        )

    try:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        os.makedirs(out_dir, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            for row in rows:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
    except OSError as e:
        refuse("OUT_WRITE_FAILED", f"{args.out}: {e}")

    print(f"wrote {len(rows)} rows to {args.out}")
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
