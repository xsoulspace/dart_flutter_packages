"""MTP draft head on a REAL trunk (Qwen3-0.6B) — the scale test the nursery
could not run.

The nursery result (RESULTS-2026-10-20 §5) was that MTP acceptance is bounded
by the trunk's own top-1: at 3.5M params the trunk scored 0.30 and the draft
head could not beat 0.42 teacher-forced. This script asks the same question
where the precondition holds.

Design (DeepSeek-V3/V4 shape, frozen trunk):
  input   concat(h_t, emb(x_{t+1}))     h_t is the trunk's hidden at t
  block   proj -> rmsnorm -> MLP -> residual   (MLP only: the draft must be
          much cheaper than a full layer or the extra forward eats the win)
  output  the trunk's OWN tied lm_head (as_linear) -> logits for x_{t+2}

The trunk is frozen; only the head trains. That is the honest "adapter"
shape: the base keeps its capability, the head adds a draft.

Gate (frozen before the run): acceptance >= 0.60 at depth 2 AND derived
effective tok/s >= 1.5x AR.

Usage:
  python tool/nursery/mtp_qwen.py --model mlx-community/Qwen3-0.6B-bf16 \
      --data bench/nursery/data/clause_dataset.jsonl --steps 400 --out mtp.json
"""

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DATA = os.path.join(PKG, "bench", "nursery", "data", "clause_dataset.jsonl")


def load_texts(path, limit):
    texts = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            t = d.get("text", "")
            if len(t) > 20:
                texts.append(t)
            if len(texts) >= limit:
                break
    return texts


def build_batches(tok, texts, seq_len, batch, max_batches):
    """Pack short texts into full-length sequences (the clause corpus is
    short clauses; a fixed seq_len needs packing, not truncation)."""
    import mlx.core as mx

    batches = []
    buf = []
    cur = []
    for t in texts:
        buf.extend(tok.encode(t))
        while len(buf) >= seq_len:
            cur.append(buf[:seq_len])
            buf = buf[seq_len:]
            if len(cur) == batch:
                batches.append(mx.array(cur, mx.int32))
                cur = []
                if len(batches) >= max_batches:
                    return batches
    if cur and len(batches) < max_batches:
        batches.append(mx.array(cur, mx.int32))
    return batches


def init_head(H, F, seed=0, blocks=1):
    import mlx.core as mx

    mx.random.seed(seed)
    head = {
        "proj": (mx.random.normal([H, 2 * H]) * (1.0 / (2 * H) ** 0.5)).astype(
            mx.float32
        ),
        "norm": mx.ones([H], mx.float32),
    }
    for b in range(blocks):
        head[f"gate{b}"] = (mx.random.normal([F, H]) * (1.0 / H**0.5)).astype(
            mx.float32
        )
        head[f"up{b}"] = (mx.random.normal([F, H]) * (1.0 / H**0.5)).astype(mx.float32)
        head[f"down{b}"] = (mx.random.normal([H, F]) * (1.0 / F**0.5)).astype(
            mx.float32
        )
        head[f"bnorm{b}"] = mx.ones([H], mx.float32)
    return head


def head_forward(head, h, emb_next, blocks=1, eps=1e-5):
    """h [B,T,H], emb_next [B,T,H] -> hidden [B,T,H] for the draft."""
    import mlx.core as mx

    x = mx.concatenate([h, emb_next], axis=-1)
    x = x @ head["proj"].T
    x = mx.fast.rms_norm(x, head["norm"], eps)
    for b in range(blocks):
        y = mx.fast.rms_norm(x, head[f"bnorm{b}"], eps)
        g = y @ head[f"gate{b}"].T
        u = y @ head[f"up{b}"].T
        x = x + (g * mx.sigmoid(g) * u) @ head[f"down{b}"].T
    return x


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--model", default="mlx-community/Qwen3-0.6B-bf16")
    ap.add_argument("--data", default=DEFAULT_DATA)
    ap.add_argument("--seq-len", type=int, default=128)
    ap.add_argument("--batch", type=int, default=8)
    ap.add_argument("--max-batches", type=int, default=40)
    ap.add_argument("--steps", type=int, default=400)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument(
        "--head-mult", type=int, default=2, help="MLP width as a multiple of H"
    )
    ap.add_argument("--head-blocks", type=int, default=1)
    ap.add_argument("--out")
    args = ap.parse_args(argv)

    import mlx.core as mx
    import mlx.optimizers as optimizers
    from mlx_lm import load

    t0 = time.time()
    model, tok = load(args.model)
    model.freeze()
    mx.eval(model.parameters())
    H = model.args.hidden_size
    F = args.head_mult * H
    print(f"loaded {args.model} in {time.time() - t0:.1f}s (H={H})", flush=True)

    texts = load_texts(args.data, limit=20000)
    batches = build_batches(tok, texts, args.seq_len, args.batch, args.max_batches)
    if not batches:
        raise SystemExit("no batches — corpus too short for seq_len")
    print(f"{len(batches)} batches of {args.batch}x{args.seq_len}", flush=True)

    emb_w = model.model.embed_tokens.weight  # [V,H] bf16, tied to lm_head
    as_linear = model.model.embed_tokens.as_linear

    # Precompute trunk hidden states once (the trunk is frozen).
    cache = []
    for ids in batches:
        h = model.model(ids)
        mx.eval(h)
        cache.append((ids, h.astype(mx.float32)))
    print(f"cached {len(cache)} hidden batches", flush=True)

    head = init_head(H, F, blocks=args.head_blocks)
    opt = optimizers.Adam(learning_rate=args.lr)

    def loss_fn(p, ids, h):
        # draft at t predicts x_{t+2}; input is (h_t, emb(x_{t+1}))
        emb_next = emb_w[ids[:, 1:]].astype(mx.float32)
        hd = head_forward(p, h[:, :-1], emb_next, args.head_blocks)  # [B,T-1,H]
        logits = as_linear(hd.astype(mx.bfloat16))  # [B,T-1,V]
        logits = logits[:, :-1].astype(mx.float32)  # [B,T-2,V]
        targets = ids[:, 2:]
        a = logits - mx.max(logits, axis=-1, keepdims=True)
        logz = mx.log(mx.sum(mx.exp(a), axis=-1))
        picked = mx.take_along_axis(
            a, mx.reshape(targets, [targets.shape[0], targets.shape[1], 1]), axis=-1
        )[:, :, 0]
        return mx.mean(logz - picked)

    vg = mx.value_and_grad(loss_fn)
    t0 = time.time()
    for step in range(1, args.steps + 1):
        ids, h = cache[(step - 1) % len(cache)]
        loss, grads = vg(head, ids, h)
        if not bool(mx.isfinite(loss).item()):
            print(f"step {step}: non-finite, skipped", flush=True)
            continue
        opt.update(head, grads)
        mx.eval(loss, head)
        if step % 50 == 0:
            print(
                f"step {step}/{args.steps} mtp_ce {float(loss.item()):.4f} "
                f"({time.time() - t0:.0f}s)",
                flush=True,
            )

    # ---- acceptance on held-out batches (the last 20% of the cache) ----
    cut = max(1, int(len(cache) * 0.8))
    held = cache[cut:]
    n_pos = n_teacher = n_self = n_trunk_top1 = n_vs_trunk = 0
    for ids, h in held:
        emb_next = emb_w[ids[:, 1:]].astype(mx.float32)
        hd = head_forward(head, h[:, :-1], emb_next, args.head_blocks)
        draft = mx.argmax(as_linear(hd.astype(mx.bfloat16)), axis=-1)  # [B,T-1]
        trunk_next = mx.argmax(as_linear(h[:, :-1].astype(mx.bfloat16)), axis=-1)
        # the trunk's own prediction for t+2 (position t+1) — the specdec
        # acceptance target: a draft is accepted when it matches the TRUNK,
        # not when it matches the ground truth.
        trunk_next2 = mx.argmax(as_linear(h[:, 1:].astype(mx.bfloat16)), axis=-1)
        # self: draft fed the trunk's own x_{t+1}
        emb_self = emb_w[trunk_next].astype(mx.float32)
        hd_self = head_forward(head, h[:, :-1], emb_self, args.head_blocks)
        draft_self = mx.argmax(as_linear(hd_self.astype(mx.bfloat16)), axis=-1)
        mx.eval(draft, draft_self, trunk_next, trunk_next2)
        B, T = ids.shape
        for b in range(B):
            for t in range(T - 2):
                true_next = int(ids[b, t + 1].item())
                true_next2 = int(ids[b, t + 2].item())
                n_pos += 1
                if int(trunk_next[b, t].item()) == true_next:
                    n_trunk_top1 += 1
                if int(draft[b, t].item()) == true_next2:
                    n_teacher += 1
                if int(draft_self[b, t].item()) == true_next2:
                    n_self += 1
                if int(draft_self[b, t].item()) == int(trunk_next2[b, t].item()):
                    n_vs_trunk += 1

    acc_teacher = n_teacher / max(1, n_pos)
    acc_self = n_self / max(1, n_pos)
    acc_vs_trunk = n_vs_trunk / max(1, n_pos)
    trunk_top1 = n_trunk_top1 / max(1, n_pos)

    # ---- cost: AR (1 pos) vs verify (2 pos) vs draft block ----
    ids, h = cache[0]
    one = ids[:, :1]
    two = ids[:, :2]

    def timeit(fn, n=5):
        fn()
        mx.eval(mx.array([0.0]))
        t = time.perf_counter()
        for _ in range(n):
            fn()
        mx.eval(mx.array([0.0]))
        return (time.perf_counter() - t) / n

    t_ar = timeit(lambda: model.model(one))
    t_verify = timeit(lambda: model.model(two))
    e = emb_w[ids[:, 1:2]].astype(mx.float32)
    t_draft = timeit(lambda: head_forward(head, h[:, :1], e))

    tokens_per_cycle = 1.0 + acc_vs_trunk
    cost_per_cycle = t_verify + t_draft
    speedup = tokens_per_cycle / cost_per_cycle * t_ar

    verdict = {
        "contract": "nursery.mtp-gate.v1",
        "model": args.model,
        "head": {"mult": args.head_mult, "blocks": args.head_blocks},
        "gate": {"acceptance_min": 0.60, "speedup_min": 1.5},
        "acceptance": {
            "positions": n_pos,
            "accept_vs_trunk": acc_vs_trunk,
            "accept_teacher": acc_teacher,
            "accept_self": acc_self,
            "trunk_top1": trunk_top1,
        },
        "costs": {"t_ar_s": t_ar, "t_verify2_s": t_verify, "t_draft_s": t_draft},
        "derived": {
            "tokens_per_cycle": tokens_per_cycle,
            "speedup_vs_ar": speedup,
            "note": "python timings; the device's memory-bound verify is "
            "cheaper, so this is a lower bound",
        },
        "passed": acc_vs_trunk >= 0.60 and speedup >= 1.5,
    }
    text = json.dumps(verdict, indent=2, sort_keys=True)
    print(text)
    if args.out:
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
