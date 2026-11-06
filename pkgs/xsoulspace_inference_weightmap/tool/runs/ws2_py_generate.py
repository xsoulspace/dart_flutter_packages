#!/usr/bin/env python3
"""ws2_py_generate.py - WS-2 PYTHON REFERENCE generator (mlx-lm boundary).

PYTHON-FIRST LAW (cross_engine.dart, frozen): python_mlxlm is the REFERENCE
engine; the Rust engine is the CANDIDATE that must match it. This script
produces the reference half of the WS-2 cross-engine agreement run.

Sampler contract (matches tool/nursery/wm_qwen35_digest.py in
xsoulspace_inference_mlx_native, frozen there as the PYTHON-FIRST parity
contract):
  - greedy token choice: next = argmax(logits - logsumexp(logits, keepdims))
  - EOS stop OFF: the stream runs EXACTLY cap steps (never truncates at EOS)
  - prompt encoding mirrors stream_generate: tokenizer.encode(prompt,
    add_special_tokens = bos_token is None)
  - prefill mirrors generate_step: chunks of <= 2048 tokens over
    prompt[:-1]; the last prompt token is the first decode step

Surface (frozen in cells_frozen_A3.json): chat template with " /no_think"
appended to the user content; caps from surface.caps (G0=64, G2=256).

Loop-rate bookkeeping (A3 semantics, computed from the EOS-off stream):
  content_tokens = index of the first generated EOS id (tokenizer
  eos_token_ids), else cap;  cap_hit = content_tokens >= cap.  Under greedy
  determinism this equals the finish_reason semantics a3_battery.py measured
  (an EOS stop at index i yields exactly content_n = i).

Modes:
  render    (CPU only) tokenizer-only pass over the frozen cells file:
            writes the prompts json BOTH engines consume (one rendering,
            identical prompt strings across engines and mirrors).
              --base SNAPSHOT --cells FILE --groups G0,G2 --out prompts.json
  generate  (GPU; run under the device lock) loads one mirror with
            mlx_lm.load, generates every prompt, writes the jsonl:
              --model DIR --prompts prompts.json --mirror NAME --out FILE
            jsonl row: {mirror, prompt_id, token_ids, text, tokens,
                        evidence{...}} (the five required keys plus a
            nested evidence object; wall_ms rows are NON-CLAIMS).

Exit codes (errors NAMED on stderr as 'CODE: detail', never silent):
  0 ok; 1 named error:
    ARGS_INVALID CELLS_FILE_UNREADABLE GROUP_UNKNOWN BASE_MISSING
    PROMPTS_FILE_UNREADABLE PROMPTS_MALFORMED MODEL_LOAD_ERROR
    MLX_UNAVAILABLE OUT_UNWRITABLE MIRROR_DIR_MISSING
"""

import argparse
import hashlib
import json
import os
import sys
import time
from datetime import datetime, timezone

EXIT_OK = 0
EXIT_FAIL = 1

PREFILL_STEP_SIZE = 2048  # frozen (wm_qwen35_digest.py contract)


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return EXIT_FAIL


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def load_cells(cells_path, groups):
    try:
        bank = json.load(open(cells_path, encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise SystemExit(fail("CELLS_FILE_UNREADABLE",
                              "%s (%s)" % (cells_path, exc)))
    cells = []
    for g in groups:
        if g not in bank["cells"]:
            raise SystemExit(fail("GROUP_UNKNOWN", g))
        cells.extend(bank["cells"][g])
    # cap from the frozen surface table (authoritative over cell-level cap,
    # same rule as a3_battery.py)
    for c in cells:
        c["cap"] = bank["surface"]["caps"][c["group"]]
    return cells, bank


def mode_render(args):
    if not os.path.isdir(args.base):
        return fail("BASE_MISSING", args.base)
    groups = [g.strip() for g in args.groups.split(",") if g.strip()]
    cells, bank = load_cells(args.cells, groups)
    try:
        from pathlib import Path

        from mlx_lm.tokenizer_utils import load as load_tokenizer
    except ImportError as exc:
        return fail("MLX_UNAVAILABLE", str(exc))
    tok = load_tokenizer(Path(args.base))
    rendered = []
    for c in cells:
        msgs = [{"role": "user", "content": c["prompt"] + " /no_think"}]
        templated = tok.apply_chat_template(
            msgs, add_generation_prompt=True, tokenize=False
        )
        rendered.append({
            "prompt_id": c["id"],
            "group": c["group"],
            "cap": c["cap"],
            "prompt": c["prompt"],
            "templated": templated,
        })
    out = {
        "artifact": "ws2_prompts",
        "created_utc": now(),
        "tool": "ws2_py_generate.py render",
        "base_dir": os.path.abspath(args.base),
        "cells_file_sha256": sha256_file(args.cells),
        "cells_file": os.path.abspath(args.cells),
        "surface_template": bank["surface"]["template"],
        "add_special_tokens": tok.bos_token is None,
        "eos_token_ids": sorted(int(i) for i in tok.eos_token_ids),
        "cells": rendered,
    }
    try:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(out, fh, ensure_ascii=False, indent=1)
    except OSError as exc:
        return fail("OUT_UNWRITABLE", str(exc))
    print("RENDER_OK %d cells -> %s (eos=%s)"
          % (len(rendered), args.out, out["eos_token_ids"]))
    return EXIT_OK


def greedy_stream(mx, model, prompt_ids, max_tokens):
    """EXACT wm_qwen35_digest.py greedy_logits_stream minus the logits
    digest capture: chunked prefill over prompt[:-1], then max_tokens steps
    of next = argmax(logits - logsumexp(logits, keepdims)); EOS stop OFF."""
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
    ids = []
    for _step in range(max_tokens):
        logits = model(y[None], cache=cache)[0, -1, :]
        mx.eval(logits)
        logprobs = logits - mx.logsumexp(logits, keepdims=True)
        next_token = int(mx.argmax(logprobs, axis=-1))
        ids.append(next_token)
        y = mx.array([next_token])
    return ids


def mode_generate(args):
    if not os.path.isdir(args.model):
        return fail("MIRROR_DIR_MISSING", args.model)
    try:
        prompts = json.load(open(args.prompts, encoding="utf-8"))
        cells = prompts["cells"]
        eos_ids = set(prompts["eos_token_ids"])
        assert isinstance(cells, list) and cells
    except (OSError, ValueError, KeyError, AssertionError) as exc:
        return fail("PROMPTS_FILE_UNREADABLE",
                    "%s (%s)" % (args.prompts, exc))
    try:
        import importlib.metadata as md

        import mlx.core as mx
        from mlx_lm import load
    except ImportError as exc:
        return fail("MLX_UNAVAILABLE", str(exc))

    shard = os.path.join(args.model, "model.safetensors")
    model_sha = sha256_file(shard) if os.path.isfile(shard) else None
    try:
        t_load = time.time()
        model, tok = load(args.model)
        load_s = round(time.time() - t_load, 2)
    except Exception as exc:
        return fail("MODEL_LOAD_ERROR", "%s (%s)" % (args.model, exc))
    add_special = tok.bos_token is None
    if add_special != prompts["add_special_tokens"]:
        return fail("PROMPTS_MALFORMED",
                    "add_special_tokens drift: prompts file says %s, mirror "
                    "tokenizer says %s" % (prompts["add_special_tokens"],
                                           add_special))

    rows = []
    t_batch = time.time()
    for i, cell in enumerate(cells):
        prompt_ids = [int(x) for x in tok.encode(
            cell["templated"], add_special_tokens=add_special)]
        cap = int(cell["cap"])
        t0 = time.time()
        ids = greedy_stream(mx, model, prompt_ids, cap)
        wall_ms = int((time.time() - t0) * 1000)
        first_eos = next((k for k, t in enumerate(ids) if t in eos_ids), None)
        content_n = first_eos if first_eos is not None else cap
        cap_hit = content_n >= cap
        text = tok.decode(ids)
        row = {
            # ---- required WS-2 jsonl schema ----
            "mirror": args.mirror,
            "prompt_id": cell["prompt_id"],
            "token_ids": ids,
            "text": text,
            "tokens": len(ids),
            # ---- evidence (non-criterion unless named) ----
            "evidence": {
                "engine": "python_mlxlm",
                "group": cell["group"],
                "cap": cap,
                "prompt_token_ids": prompt_ids,
                "content_tokens": content_n,
                "first_eos_index": first_eos,
                "cap_hit": cap_hit,
                "eos_stop": False,
                "sampler": "greedy: argmax(logits - logsumexp(logits))",
                "prefill_step_size": PREFILL_STEP_SIZE,
                "model_dir": os.path.abspath(args.model),
                "model_sha256": model_sha,
                "load_s": load_s,
                "wall_ms": wall_ms,
                "wall_ms_claim": False,
                "at": now(),
            },
        }
        rows.append(row)
        print("[%d/%d] %s %s tok=%d/%d content=%d hit=%s %.1fs"
              % (i + 1, len(cells), args.mirror, cell["prompt_id"],
                 len(ids), cap, content_n, cap_hit, wall_ms / 1000.0))

    meta = {
        "mirror": args.mirror,
        "prompt_id": "__meta__",
        "token_ids": [],
        "text": "",
        "tokens": 0,
        "evidence": {
            "engine": "python_mlxlm",
            "kind": "batch_meta",
            "tool": "ws2_py_generate.py generate",
            "prompts_file": os.path.abspath(args.prompts),
            "prompts_file_sha256": sha256_file(args.prompts),
            "cells": len(rows),
            "batch_wall_s": round(time.time() - t_batch, 1),
            "batch_wall_s_claim": False,
            "mlx_version": md.version("mlx"),
            "mlx_lm_version": md.version("mlx-lm"),
            "transformers_version": md.version("transformers"),
            "python_version": sys.version.split()[0],
            "model_sha256": model_sha,
            "eos_token_ids": sorted(eos_ids),
            "created_utc": now(),
        },
    }
    try:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(json.dumps(r, ensure_ascii=False) + "\n")
            fh.write(json.dumps(meta, ensure_ascii=False) + "\n")
    except OSError as exc:
        return fail("OUT_UNWRITABLE", str(exc))
    print("GENERATE_OK %s %d cells -> %s" % (args.mirror, len(rows), args.out))
    return EXIT_OK


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("mode", choices=["render", "generate"])
    ap.add_argument("--base", help="render: base snapshot dir (tokenizer)")
    ap.add_argument("--cells", help="render: cells_frozen_A3.json")
    ap.add_argument("--groups", default="G0,G2")
    ap.add_argument("--model", help="generate: mirror dir")
    ap.add_argument("--prompts", help="generate: prompts json from render")
    ap.add_argument("--mirror", help="generate: mirror name for the jsonl")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if args.mode == "render":
        if not (args.base and args.cells):
            return fail("ARGS_INVALID", "render needs --base and --cells")
        return mode_render(args)
    if not (args.model and args.prompts and args.mirror):
        return fail("ARGS_INVALID",
                    "generate needs --model, --prompts and --mirror")
    return mode_generate(args)


if __name__ == "__main__":
    sys.exit(main())
