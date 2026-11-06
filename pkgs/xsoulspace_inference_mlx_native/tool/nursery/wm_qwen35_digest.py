#!/usr/bin/env python3
"""wm_qwen35_digest.py — Qwen3.5 parity-fixture dumper (PYTHON FIRST half).

The digest written here is the CONTRACT a Rust loader must match: greedy
token ids plus a SHA-256 over the model's raw logits at the first 8 greedy
steps, fp32-cast and rounded to 6 decimal places. The rounding rule is
stated exactly below and embedded in the output JSON ("rounding_rule").

ROUNDING / DIGEST RULE (normative):
  For each of the first `digest_steps` = min(8, max_tokens) greedy steps:
  1. `logits` is the model's raw output row for the last position
     (shape [vocab_size], in vocab-index order), taken BEFORE any
     logsumexp/logprob transform, in whatever dtype the model emits
     (bfloat16 for this checkpoint; recorded as logits_dtype).
  2. The row is cast to float32 (`mx.astype(mx.float32)` — exact widening
     from bf16) and each value v is formatted with C fixed-point "%.6f":
     the correctly rounded 6-decimal representation of the exact binary
     value, ties-to-even at an exact midpoint. Python "%.6f" and Rust
     "{:.6}" agree on these inputs (both round the exact binary double;
     the fp32 -> fp64 widening is exact). -0.0 formats as "-0.000000".
  3. Step text = the formatted values joined with "," (no spaces).
  4. Digest input = step texts joined with "\\n", plus one trailing "\\n",
     UTF-8 encoded. The digest is its lowercase hex SHA-256.
  5. per_step_sha256[i] = SHA-256 of (step_text[i] + "\\n").encode("utf-8")
     — diagnostic localisation, same rule per step.
  Token choice mirrors mlx_lm's greedy sampler exactly:
  next = argmax(logits - logsumexp(logits, keepdims=True)).
  Prompt encoding mirrors stream_generate: tokenizer.encode(prompt,
  add_special_tokens=True-iff-no-bos). Prefill mirrors generate_step:
  chunks of <= 2048 tokens over prompt[:-1], then the last token is the
  first step. EOS stop is OFF (house law: parity streams are byte-identical
  oracles and never truncate at EOS); the stream runs exactly max_tokens
  steps.

Args:
  --model DIR      checkpoint dir
  --prompts FILE   one prompt per line; blank lines skipped
  --max-tokens N   greedy steps per prompt (>= 1)
  --out JSON       fixture path (provenance + per-prompt results)
  --dry-run        print the plan JSON (mlx NOT imported) and exit 0

Output JSON per prompt:
  {prompt_id, prompt, prompt_token_count, first_32_token_ids,
   generated_steps, digest_steps, vocab_size, logits_dtype,
   per_step_sha256, logits_digest_sha256_of_first_8_steps_fp32_rounded_6dp}
  first_32_token_ids holds min(32, max_tokens) ids (EOS is not a stop).

Exit codes (NAMED refusals "CODE: message" on stderr, never silent):
  0 OK; 1 INTERNAL; 2 refusal: MODEL_DIR_MISSING, CONFIG_MISSING,
  CONFIG_UNPARSEABLE, ARCH_UNSUPPORTED, PROMPTS_MISSING, PROMPTS_EMPTY,
  MAX_TOKENS_INVALID, MLX_UNAVAILABLE, OUT_WRITE_FAILED

The validation block is mirrored verbatim in wm_qwen35_generate.py and
wm_qwen35_bench.py (scope law: the three boundary scripts stay standalone).

Run via the venv resolver:
  WM_PY=$(tool/nursery/wm_pyenv.sh) && "$WM_PY" tool/nursery/wm_qwen35_digest.py ...
"""

import argparse
import hashlib
import json
import os
import sys
import time

SUPPORTED_MODEL_TYPES = ("qwen3_5",)
DIGEST_STEPS = 8
FIRST_N_TOKEN_IDS = 32
PREFILL_STEP_SIZE = 2048


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


ROUNDING_RULE = (
    "For each of the first digest_steps=min(8, max_tokens) greedy steps: the "
    "model's raw logits row for the last position (length vocab_size, "
    "vocab-index order, taken BEFORE logsumexp, in the model's output dtype) "
    "is cast to float32 (exact widening from bfloat16) and every value is "
    "formatted with C fixed-point '%.6f' — the correctly rounded 6-decimal "
    "representation of the exact binary value, ties-to-even at an exact "
    "midpoint (Python '%.6f' and Rust '{:.6}' agree on these inputs; -0.0 "
    "formats as '-0.000000'). Step text = values joined with ',' (no "
    "spaces). Digest input = step texts joined with '\\n' plus one trailing "
    "'\\n', UTF-8 encoded; the digest is its lowercase hex SHA-256. "
    "per_step_sha256[i] = SHA-256 of (step_text[i] + '\\n').encode('utf-8'). "
    "Token choice: next = argmax(logits - logsumexp(logits, keepdims=True)), "
    "mirroring mlx_lm's greedy sampler. Prompt encoding mirrors "
    "stream_generate (add_special_tokens iff no bos); prefill mirrors "
    "generate_step (chunks of <=2048 over prompt[:-1], last token is the "
    "first step). EOS stop is OFF; the stream runs exactly max_tokens steps."
)


def parse_args(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--model", required=True)
    ap.add_argument("--prompts", required=True)
    ap.add_argument("--max-tokens", required=True, type=int)
    ap.add_argument("--out", required=True)
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args(argv)


def greedy_logits_stream(mx, model, prompt_ids, max_tokens, digest_steps):
    """Yield (raw_logits_row, next_token) per greedy step, mirroring
    mlx_lm.generate.generate_step's structure (prefill chunks + per-step
    forwards) with EOS stop OFF."""
    from mlx_lm.models.cache import make_prompt_cache

    cache = make_prompt_cache(model)
    prompt = mx.array(prompt_ids)
    total = len(prompt_ids)
    processed = 0
    cur = prompt
    while total - processed > 1:
        n = min(PREFILL_STEP_SIZE, (total - processed) - 1)
        model(cur[:n][None], cache=cache)
        mx.eval([c.state for c in cache])
        processed += n
        cur = cur[n:]
        mx.clear_cache()

    y = cur
    for _step in range(max_tokens):
        # [0, -1, :] drops batch and keeps the last position -> [vocab_size]
        logits = model(y[None], cache=cache)[0, -1, :]
        mx.eval(logits)
        logprobs = logits - mx.logsumexp(logits, keepdims=True)
        next_token = int(mx.argmax(logprobs, axis=-1))
        yield (logits if _step < digest_steps else None), next_token
        y = mx.array([next_token])


def main(argv):
    args = parse_args(argv)
    if args.max_tokens < 1:
        refuse("MAX_TOKENS_INVALID", f"--max-tokens must be >= 1, got {args.max_tokens}")
    prompts = read_prompts(args.prompts)
    model_type, architectures = read_arch(args.model)
    digest_steps = min(DIGEST_STEPS, args.max_tokens)

    if args.dry_run:
        plan = {
            "script": "wm_qwen35_digest.py",
            "model": os.path.abspath(args.model),
            "arch": model_type,
            "architectures": architectures,
            "prompt_count": len(prompts),
            "max_tokens": args.max_tokens,
            "digest_steps": digest_steps,
            "out": os.path.abspath(args.out),
            "mlx_imported": False,
        }
        print(json.dumps(plan))
        return 0

    # Runtime imports (PYTHON-BOUNDARY idiom).
    try:
        import importlib.metadata as importlib_metadata

        import mlx.core as mx
        from mlx_lm import load
    except ImportError as e:
        refuse("MLX_UNAVAILABLE", f"mlx/mlx_lm import failed: {e}")

    t_load0 = time.perf_counter()
    model, tokenizer = load(args.model)
    load_ms = (time.perf_counter() - t_load0) * 1000.0

    # Mirror stream_generate's special-token inference for the raw prompt.
    bos = getattr(tokenizer, "bos_token", None)
    add_special = bos is None

    results = []
    for prompt_id, prompt in enumerate(prompts):
        prompt_ids = [int(i) for i in tokenizer.encode(prompt, add_special_tokens=add_special)]
        step_texts = []
        token_ids = []
        logits_dtype = None
        vocab_size = None
        for raw_logits, next_token in greedy_logits_stream(
            mx, model, prompt_ids, args.max_tokens, digest_steps
        ):
            token_ids.append(next_token)
            if raw_logits is not None:
                row = raw_logits.astype(mx.float32)
                mx.eval(row)
                vals = row.tolist()
                if logits_dtype is None:
                    logits_dtype = str(raw_logits.dtype)
                    vocab_size = len(vals)
                step_texts.append(",".join("%.6f" % v for v in vals))
        per_step = [
            hashlib.sha256((t + "\n").encode("utf-8")).hexdigest() for t in step_texts
        ]
        digest = hashlib.sha256(
            ("\n".join(step_texts) + "\n").encode("utf-8")
        ).hexdigest()
        results.append(
            {
                "prompt_id": prompt_id,
                "prompt": prompt,
                "prompt_token_count": len(prompt_ids),
                "prompt_token_ids": prompt_ids,
                "first_32_token_ids": token_ids[:FIRST_N_TOKEN_IDS],
                "generated_steps": len(token_ids),
                "digest_steps": len(step_texts),
                "vocab_size": vocab_size,
                "logits_dtype": logits_dtype,
                "per_step_sha256": per_step,
                "logits_digest_sha256_of_first_8_steps_fp32_rounded_6dp": digest,
            }
        )

    fixture = {
        "rounding_rule": ROUNDING_RULE,
        "provenance": {
            "script": "wm_qwen35_digest.py",
            "model_dir": os.path.abspath(args.model),
            "model_type": model_type,
            "architectures": architectures,
            "mlx_version": importlib_metadata.version("mlx"),
            "mlx_lm_version": importlib_metadata.version("mlx-lm"),
            "python_version": sys.version.split()[0],
            "max_tokens": args.max_tokens,
            "digest_steps": digest_steps,
            "prefill_step_size": PREFILL_STEP_SIZE,
            "sampler": "greedy: argmax(logits - logsumexp(logits))",
            "eos_stop": False,
            "load_ms": round(load_ms, 3),
            "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        },
        "results": results,
    }
    try:
        out_dir = os.path.dirname(os.path.abspath(args.out))
        os.makedirs(out_dir, exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(fixture, f, ensure_ascii=False, indent=2)
            f.write("\n")
    except OSError as e:
        refuse("OUT_WRITE_FAILED", f"{args.out}: {e}")

    print(f"wrote digest fixture ({len(results)} prompts) to {args.out}")
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
