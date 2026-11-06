#!/usr/bin/env python3
"""a3_battery.py - frozen-cell battery runner (generation instrument only).

Surface (frozen in cells_frozen_A3.json): chat template with " /no_think"
appended to the user content, greedy (temp 0.0), mlx_lm stream_generate with
EXACT generated-token counts. This script performs NO scoring beyond the cap
bookkeeping - certification scoring runs from the frozen cells file in the
Dart stage (a3_score.dart) against these raw outputs.

Usage:
  python3 -I a3_battery.py --model <dir> --cells cells_frozen_A3.json \
      --groups G0,G1,G2 --out <outputs.jsonl> \
      [--repair <repair_spec.json> --repair-out <outputs_R.jsonl> \
       --repair-receipt <receipt.json>]

--repair applies {tensors:[{name, columns, direction, scale}]} to the LOADED
model in memory (W[:, cols] += scale*direction in fp32, cast back to the
stored dtype - the same merge law as make_mirror.py; scale is negative for a
removal edit), records post-repair tensor digests, and runs the battery again.
The model on disk is never touched.

Exit codes: 0 ok; 1 named error on stderr ('CODE: detail'):
  CELLS_FILE_UNREADABLE GROUP_UNKNOWN MODEL_LOAD_ERROR REPAIR_SPEC_MALFORMED
  TENSOR_NOT_IN_MODEL OUT_UNWRITABLE MLX_UNAVAILABLE
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


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return EXIT_FAIL


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def resolve(model, name):
    """Walk 'model.layers.15.mlp.down_proj.weight' to (parent, attr)."""
    parts = name.split(".")
    node = model
    for i, part in enumerate(parts):
        if i == len(parts) - 1:
            return node, part
        if part.isdigit():
            node = node[int(part)]
        else:
            node = getattr(node, part)
    raise KeyError(name)


def run_battery(model, tok, cells, out_path, stage, extra=None):
    from mlx_lm import stream_generate
    from mlx_lm.sample_utils import make_sampler
    sampler = make_sampler(temp=0.0)  # greedy (frozen sampler config)
    rows = []
    with open(out_path, "w", encoding="utf-8") as fh:
        for cell in cells:
            msgs = [{"role": "user", "content": cell["prompt"] + " /no_think"}]
            prompt = tok.apply_chat_template(
                msgs, add_generation_prompt=True, tokenize=False
            )
            t0 = time.time()
            text = []
            n = 0
            finish = None
            for resp in stream_generate(
                model, tok, prompt=prompt, max_tokens=cell["cap"],
                sampler=sampler,
            ):
                n += 1
                text.append(resp.text)
                fr = getattr(resp, "finish_reason", None)
                if fr:
                    finish = fr
            out = "".join(text)
            # content-token count excludes the EOS yield ("stop" runs);
            # cap_hit is decided by finish_reason when present (exact), else
            # by the frozen count>=cap rule.
            content_n = n - 1 if finish == "stop" else n
            cap_hit = (finish == "length") if finish else (content_n >= cell["cap"])
            wall_ms = int((time.time() - t0) * 1000)
            row = {
                "stage": stage,
                "cell_id": cell["id"],
                "group": cell["group"],
                "cap": cell["cap"],
                "generated_tokens": content_n,
                "yields_incl_eos": n,
                "cap_hit": cap_hit,
                "finish_reason": finish,
                "wall_ms": wall_ms,
                "wall_ms_claim": False,
                "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "output": out,
                "output_sha256": sha256_bytes(out.encode("utf-8")),
            }
            if extra:
                row.update(extra)
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")
            rows.append(row)
            print("[%s/%s] %s tok=%d/%d hit=%s finish=%s %.1fs"
                  % (stage, cell["group"], cell["id"], content_n, cell["cap"],
                     cap_hit, finish, wall_ms / 1000.0))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--cells", required=True)
    ap.add_argument("--groups", required=True, help="comma list, e.g. G0,G1,G2")
    ap.add_argument("--out", default=None,
                    help="M-stage outputs jsonl (omit to run repair stage only)")
    ap.add_argument("--repair", default=None)
    ap.add_argument("--repair-out", default=None)
    ap.add_argument("--repair-receipt", default=None)
    args = ap.parse_args()

    try:
        bank = json.load(open(args.cells, encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return fail("CELLS_FILE_UNREADABLE", str(exc))
    groups = [g.strip() for g in args.groups.split(",") if g.strip()]
    cells = []
    for g in groups:
        if g not in bank["cells"]:
            return fail("GROUP_UNKNOWN", g)
        cells.extend(bank["cells"][g])
    # cap from the frozen surface table (authoritative over cell-level cap)
    for c in cells:
        c["cap"] = bank["surface"]["caps"][c["group"]]

    if args.out is None and not args.repair:
        return fail("GROUP_UNKNOWN", "nothing to run: --out or --repair required")

    try:
        import mlx.core as mx
        from mlx_lm import load
    except ImportError as exc:
        return fail("MLX_UNAVAILABLE", str(exc))
    try:
        model, tok = load(args.model)
    except Exception as exc:
        return fail("MODEL_LOAD_ERROR", "%s (%s)" % (args.model, exc))

    if args.out:
        try:
            os.makedirs(os.path.dirname(os.path.abspath(args.out)),
                        exist_ok=True)
            run_battery(model, tok, cells, args.out, "M")
        except OSError as exc:
            return fail("OUT_UNWRITABLE", str(exc))

    if args.repair:
        if not args.repair_out:
            return fail("REPAIR_SPEC_MALFORMED",
                        "--repair requires --repair-out")
        try:
            spec = json.load(open(args.repair, encoding="utf-8"))
            tensors = spec["tensors"]
            assert isinstance(tensors, list) and tensors
        except (OSError, ValueError, KeyError, AssertionError) as exc:
            return fail("REPAIR_SPEC_MALFORMED", str(exc))
        repaired = []
        import numpy as np
        for t in tensors:
            try:
                parent, attr = resolve(model, t["name"])
                w = getattr(parent, attr)
                cols = mx.array([int(c) for c in t["columns"]])
                delta = mx.array(t["direction"], dtype=mx.float32) * float(t["scale"])
                wf = w.astype(mx.float32).at[:, cols].add(delta[:, None])
                new_w = wf.astype(w.dtype)
                mx.eval(new_w)
                setattr(parent, attr, new_w)
                repaired.append({
                    "tensor": t["name"],
                    "scale": t["scale"],
                    "columns": len(t["columns"]),
                    "direction_sha256": sha256_bytes(
                        json.dumps(t["direction"]).encode()),
                    "post_repair_tensor_f32_sha256": sha256_bytes(
                        np.array(new_w.astype(mx.float32)).tobytes()),
                })
            except (KeyError, IndexError, AttributeError, TypeError,
                    ValueError) as exc:
                return fail("TENSOR_NOT_IN_MODEL",
                            "%s (%s)" % (t.get("name"), exc))
        mx.eval(model.parameters())
        receipt = {
            "tool": "a3_battery.py --repair",
            "model_dir": os.path.abspath(args.model),
            "model_on_disk_untouched": True,
            "merge_law": "W[:, cols] += scale*direction (fp32, cast back to stored dtype)",
            "repaired": repaired,
            "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        if args.repair_receipt:
            with open(args.repair_receipt, "w", encoding="utf-8") as fh:
                json.dump(receipt, fh, indent=1)
        try:
            run_battery(model, tok, cells, args.repair_out, "R")
        except OSError as exc:
            return fail("OUT_UNWRITABLE", str(exc))
        print("REPAIR_OK %s" % args.repair_out)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
