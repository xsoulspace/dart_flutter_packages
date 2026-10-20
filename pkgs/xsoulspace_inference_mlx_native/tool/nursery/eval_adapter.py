"""Evaluate a Dart authoring adapter: base vs base+adapter, minimal vs rich
context, with a real `dart analyze` gate.

The endpoint is NOT "does the adapter pass more". It is the CONTEXT claim:

    an adapter should move the MINIMAL-context case more than the RICH one.

If it does, the adapter moved repo knowledge from the prompt into the
weights — which is the only reason to build one here, because context is the
measured bottleneck (RESULTS-2026-10-20 §2). If it only helps when the full
file context is present, it has learned nothing the prompt was not already
saying.

Usage:
  python tool/nursery/eval_adapter.py --tasks <eval.jsonl> \
      --model mlx-community/Qwen3-0.6B-4bit --adapter <lora dir> --out eval.json
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from build_dart_tasks import prompt as build_prompt  # noqa: E402


def extract_body(text):
    """First balanced {...} block in the completion, or None."""
    start = text.find("{")
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]
    return None


def analyze_ok(source):
    """True when `dart analyze` reports no errors for this source."""
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "probe.dart")
        with open(path, "w") as fh:
            fh.write(source)
        try:
            r = subprocess.run(
                ["dart", "analyze", "--no-fatal-warnings", path],
                capture_output=True,
                text=True,
                timeout=60,
            )
        except Exception:
            return False, "analyze failed to run"
        out = (r.stdout + r.stderr).strip()
        # `dart analyze` can exit non-zero for reasons that are not errors
        # (no pubspec, warnings). The gate is the error line, not the code.
        ok = "error -" not in out
        return ok, out.splitlines()[0] if out else ""


def run(model, tok, task, shape, max_tokens=320):
    from mlx_lm import generate

    p = build_prompt(task, shape)
    # The adapter was trained on chat turns, so inference must use the same
    # template — a raw prompt string is a different distribution.
    chat = tok.apply_chat_template(
        [{"role": "user", "content": p}],
        add_generation_prompt=True,
        tokenize=False,
    )
    text = generate(model, tok, prompt=chat, max_tokens=max_tokens, verbose=False)
    body = extract_body(text)
    return chat, text, body


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tasks", required=True)
    ap.add_argument("--model", default="mlx-community/Qwen3-0.6B-4bit")
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--limit", type=int, default=12)
    ap.add_argument("--out")
    args = ap.parse_args(argv)

    from mlx_lm import load

    tasks = [json.loads(l) for l in open(args.tasks) if l.strip()][: args.limit]
    if not tasks:
        raise SystemExit("no eval tasks")

    results = {}
    for label, adapter in (("base", None), ("adapter", args.adapter)):
        model, tok = load(args.model, adapter_path=adapter)
        for shape in ("minimal", "rich"):
            rows = []
            for t in tasks:
                p, text, body = run(model, tok, t, shape)
                ok = False
                why = "no body"
                if body:
                    src = (
                        (t["imports"] + "\n\n" if t["imports"] else "")
                        + t["signature"]
                        + "\n"
                        + body
                    )
                    ok, why = analyze_ok(src)
                rows.append(
                    {
                        "id": t["id"],
                        "prompt_tokens": len(tok.encode(p)),
                        "body": bool(body),
                        "analyze_ok": ok,
                        "why": why,
                    }
                )
            key = f"{label}/{shape}"
            results[key] = {
                "n": len(rows),
                "body_rate": sum(r["body"] for r in rows) / len(rows),
                "analyze_ok_rate": sum(r["analyze_ok"] for r in rows) / len(rows),
                "mean_prompt_tokens": sum(r["prompt_tokens"] for r in rows) / len(rows),
                "rows": rows,
            }
            print(
                f"{key}: body {results[key]['body_rate']:.2f} "
                f"analyze_ok {results[key]['analyze_ok_rate']:.2f} "
                f"prompt_tok {results[key]['mean_prompt_tokens']:.0f}",
                flush=True,
            )

    # the context claim
    base_min = results["base/minimal"]["analyze_ok_rate"]
    ad_min = results["adapter/minimal"]["analyze_ok_rate"]
    base_rich = results["base/rich"]["analyze_ok_rate"]
    ad_rich = results["adapter/rich"]["analyze_ok_rate"]
    verdict = {
        "contract": "nursery.dart-adapter.v1",
        "model": args.model,
        "adapter": os.path.abspath(args.adapter),
        "results": results,
        "delta": {
            "minimal": ad_min - base_min,
            "rich": ad_rich - base_rich,
            "context_claim_holds": (ad_min - base_min) > (ad_rich - base_rich),
        },
    }
    text = json.dumps(verdict, indent=2)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
    print(json.dumps(verdict["delta"], indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
