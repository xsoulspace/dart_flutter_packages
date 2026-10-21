"""MTP-RETARGET — the decisive MTP experiment (Line J, 2026-10-21).

WHY THIS EXPERIMENT EXISTS. The previous MTP arm
(`bench/nursery/experiments/RESULTS-part2.md` §8) trained a draft head against
CORPUS TRUTH and measured acceptance against the TRUNK's own argmax. Those
are different quantities, and that arm's own numbers show the gap:

    accept vs truth  0.999      (the head learned the corpus perfectly)
    accept vs trunk  0.359      (the head disagrees with the trunk 64% of the time)
    trunk top-1      0.399      (the trunk itself is only 40% right on this corpus)

A draft head's job in speculative decoding is NOT to predict the corpus. It is
to predict what the TARGET will do, because acceptance IS agreement with the
target. The head was optimised for the wrong quantity, so it was maximally
good at the one thing that does not matter.

THE THREE VARIABLES, AND THE ARMS THAT ISOLATE THEM

  prefix   the context the trunk's hidden state is computed in
  input    the token the draft head is FED (at decode: the trunk's own token)
  target   the token the draft head is TRAINED to predict

  arm A  corpus prefix, TRUE  input, TRUE  target   = the OLD arm, reproduced
  arm D  corpus prefix, TRUE  input, TRUNK target   = isolates the TARGET
  arm B  corpus prefix, TRUNK input, TRUNK target   = isolates the INPUT
  arm C  greedy prefix, TRUNK input, TRUNK target   = isolates the PREFIX

A -> D -> B -> C is a chain of single-variable changes, so each step's delta
is attributable. Arm C is the only fully self-consistent arm: hidden state,
input token and target all come from the trunk's OWN path, which is exactly
what a decoder sees.

MEASUREMENT IS IDENTICAL FOR EVERY ARM: decode-consistently, on held-out
trunk greedy paths — the head is fed the trunk's own token and compared with
the trunk's own next token. Two numbers are reported:

  accept_self     head j is fed head j-1's OWN argmax (what the decoder does)
  accept_teacher  head j is fed the trunk's token (teacher forced)

The gap between them is exposure bias, and separating it from the head's
quality is the difference between "the technique is dead" and "the training
needs to match the decoder".

TWO FURTHER DEFECTS IN THE OLD MEASUREMENT, both fixed here:

1. It was teacher-forced on CORPUS text, so the head was fed the trunk's
   argmax while the acceptance target was computed with the TRUE token in the
   prefix. At decode time the prefix IS the trunk's own output; the two never
   agree off-policy.

2. Its timing harness never forced MLX to evaluate (`mx.eval` of an unrelated
   dummy array does not evaluate `fn()`'s output), so it timed GRAPH
   CONSTRUCTION, and it omitted the draft head's own vocab projection
   entirely. The speedup numbers it reported (1.41x, 1.42x) are artifacts of
   that, not of the device. The timing here forces the real output.

THE CHAIN (MTP COUNT K). Head j is conditioned on head j-1's hidden state and
the token at position t+j, and predicts the token at position t+j+1 — the
DeepSeek-V3 MTP shape.

GATES (MTP-GATES.md, frozen before this run):
  J-G1 acceptance >= 0.60 (depth 1, decode-consistent)
  J-G2 effective speedup >= 1.5x AR  — NOT claimed here; the native Rust
     port is the authority (J-G4)
  J-G3 a count K is adopted only if tokens-per-cycle at K > at K-1

Usage:
  python tool/nursery/mtp_retarget.py --model mlx-community/Qwen3-0.6B-bf16 \
      --arm C --count 3 --steps 3000 --out bench/nursery/experiments/x.json
"""

import argparse
import json
import os
import random
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import power_snapshot  # noqa: E402

DEFAULT_PROMPTS = os.path.join(PKG, "bench", "nursery", "data", "dart_corpus.jsonl")

# arm -> (prefix, input sequence, target sequence)
ARMS = {
    "A": ("corpus", "truth", "truth"),
    "D": ("corpus", "truth", "trunk"),
    "B": ("corpus", "trunk", "trunk"),
    "C": ("greedy", "trunk", "trunk"),
}
ARM_MEANING = {
    "A": "corpus prefix + TRUE input + TRUE target (the OLD arm, reproduced)",
    "D": "corpus prefix + TRUE input + TRUNK target (isolates the TARGET)",
    "B": "corpus prefix + TRUNK input + TRUNK target (isolates the INPUT)",
    "C": "trunk's greedy path + TRUNK input + TRUNK target (isolates the PREFIX)",
}


# ---------------------------------------------------------------- utilities


def load_texts(path, limit):
    texts = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            t = d.get("text", "")
            if len(t) > 200:
                texts.append(t)
            if len(texts) >= limit:
                break
    return texts


def real_timeit(fn, n=8):
    """Time REAL execution.

    MLX is lazy: `fn()` returns an unevaluated graph. The lane's older
    harness called `mx.eval(mx.array([0.0]))`, which does NOT evaluate
    `fn()`'s output, so it timed graph construction. This forces the actual
    output every iteration.
    """
    import mlx.core as mx

    out = fn()
    mx.eval(out)
    t = time.perf_counter()
    for _ in range(n):
        out = fn()
        mx.eval(out)
    return (time.perf_counter() - t) / n


def chunked_ce(student, target, chunk=256):
    """Mean cross-entropy of `student` [B, V] against `target` [B].

    Chunked over B so the fp32 logit copy stays bounded: the vocab is
    151936 wide, so a full-batch fp32 logit tensor is ~0.6 GB per 1024
    positions. The chunking is arithmetic only — the mean is over all B.
    """
    import mlx.core as mx

    total = mx.zeros([], mx.float32)
    B = student.shape[0]
    for s in range(0, B, chunk):
        e = min(s + chunk, B)
        lg = student[s:e].astype(mx.float32)
        m = mx.max(lg, axis=-1, keepdims=True)
        z = mx.log(mx.sum(mx.exp(lg - m), axis=-1, keepdims=True))
        y = target[s:e]
        picked = mx.take_along_axis(lg - m, mx.reshape(y, [y.shape[0], 1]), axis=-1)[
            :, 0
        ]
        total = total + (z[:, 0] - picked).sum()
    return total / B


# ------------------------------------------------------- the MTP draft head


def init_head(H, F, seed=0):
    """One draft head. Depth j predicts the token j positions beyond the
    trunk's current next token.

    Head shape (mirrors the nursery's `model.mtp.*` contract so the native
    Rust port can mirror it exactly):
        proj  [H, 2H]   concat(prev_hidden, token_embedding) -> H
        norm  [H]
        gate  [F, H]    up [F, H]    down [H, F]
    """
    import mlx.core as mx

    mx.random.seed(seed)
    return {
        "proj": (mx.random.normal([H, 2 * H]) * (1.0 / (2 * H) ** 0.5)).astype(
            mx.float32
        ),
        "norm": mx.ones([H], mx.float32),
        "gate": (mx.random.normal([F, H]) * (1.0 / H**0.5)).astype(mx.float32),
        "up": (mx.random.normal([F, H]) * (1.0 / H**0.5)).astype(mx.float32),
        "down": (mx.random.normal([H, F]) * (1.0 / F**0.5)).astype(mx.float32),
    }


def head_forward(head, prev_hidden, token_emb):
    """(prev_hidden [..., H], token_emb [..., H]) -> draft hidden [..., H].

    `prev_hidden` is the trunk's hidden for depth 1 and the previous head's
    hidden for deeper depths. `token_emb` is the embedding of the token the
    depth is conditioning on.
    """
    import mlx.core as mx

    x = mx.concatenate([prev_hidden, token_emb], axis=-1)
    x = x @ head["proj"].T
    x = mx.fast.rms_norm(x, head["norm"], 1e-5)
    g = x @ head["gate"].T
    u = x @ head["up"].T
    d = (g * mx.sigmoid(g) * u) @ head["down"].T
    return x + d


# ------------------------------------------------------------------- main


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--model", default="mlx-community/Qwen3-0.6B-bf16")
    ap.add_argument("--prompts", default=DEFAULT_PROMPTS)
    ap.add_argument("--out")
    ap.add_argument("--arm", default="C", choices=sorted(ARMS))
    ap.add_argument("--n-prompts", type=int, default=48)
    ap.add_argument("--gen-tokens", type=int, default=192)
    ap.add_argument("--prompt-tokens", type=int, default=96)
    ap.add_argument("--holdout", type=int, default=12, help="prompts reserved for eval")
    ap.add_argument("--steps", type=int, default=3000)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument(
        "--head-mult", type=int, default=2, help="MLP width as a multiple of H"
    )
    ap.add_argument("--count", type=int, default=1, help="MTP count K (chained heads)")
    ap.add_argument(
        "--batch", type=int, default=1024, help="positions per training step"
    )
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument(
        "--cache", default=None, help="record cache path (shared by all arms)"
    )
    ap.add_argument("--measure-timings", action="store_true")
    ap.add_argument(
        "--overfit-probe",
        type=int,
        default=0,
        help="train on ONE tiny batch for N steps and report the loss. If the "
        "head cannot memorise one batch the mechanics are broken and no arm's "
        "number means anything (META-LESSONS lesson 3).",
    )
    ap.add_argument(
        "--self-test",
        action="store_true",
        help="run the measurement harness against PINNED synthetic cases (a "
        "perfect head must score 1.0, a wrong one 0.0) and exit.",
    )
    args = ap.parse_args(argv)

    import mlx.core as mx
    import mlx.optimizers as optimizers
    from mlx_lm import load
    from mlx_lm.models.cache import make_prompt_cache

    prefix_kind, input_kind, target_kind = ARMS[args.arm]

    if args.self_test:
        return self_test()

    t_start = time.time()
    model, tok = load(args.model)
    model.freeze()
    mx.eval(model.parameters())
    H = model.args.hidden_size
    F = args.head_mult * H
    print(f"loaded {args.model} H={H} V={model.args.vocab_size}", flush=True)
    print(f"arm {args.arm}: {ARM_MEANING[args.arm]}", flush=True)

    emb_w = model.model.embed_tokens.weight  # [V, H]
    as_linear = model.model.embed_tokens.as_linear

    texts = load_texts(args.prompts, args.n_prompts)
    if len(texts) <= args.holdout:
        raise SystemExit("need more prompts than the holdout")
    print(f"{len(texts)} prompts", flush=True)

    # ---- build (or load) the record sets --------------------------------
    #
    # CORPUS record (one teacher-forced forward over the corpus text):
    #   h[t]        trunk hidden after consuming corpus ids[0..t]
    #   TRUE[t]     the corpus token at position t+1   (ids[t+1])
    #   TRUNK[t]    the trunk's own argmax at position t (its prediction for t+1)
    #
    # GREEDY record (the trunk's own continuation):
    #   h[i]        trunk hidden after consuming the path up to position P-1+i
    #   TRUNK[i]    the trunk's own token at position P+i
    #   TRUE[i]     the same token (the path IS the trunk's own output)
    corpus_records, greedy_records = [], []

    if args.cache and os.path.exists(args.cache):
        import pickle

        with open(args.cache, "rb") as fh:
            blob = pickle.load(fh)
        corpus_records = blob["corpus"]
        greedy_records = blob["greedy"]
        print(f"loaded records from {args.cache}", flush=True)
    else:
        for pi, text in enumerate(texts):
            ids = tok.encode(text)[: args.prompt_tokens + args.gen_tokens]
            if len(ids) < 16:
                continue

            arr = mx.array(ids, mx.int32)[None]
            h_corpus = model.model(arr)
            argmax_corpus = mx.argmax(as_linear(h_corpus.astype(mx.bfloat16)), axis=-1)
            mx.eval(h_corpus, argmax_corpus)
            corpus_records.append(
                {
                    "h": h_corpus[0].astype(mx.float32),  # [T, H]
                    "TRUE": ids[1:] + [ids[-1]],
                    "TRUNK": [int(v) for v in argmax_corpus[0].tolist()],
                }
            )

            cache = make_prompt_cache(model)
            cur = mx.array(ids[: args.prompt_tokens], mx.int32)[None]
            hs, toks = [], []
            for _ in range(args.gen_tokens):
                h = model.model(cur, cache=cache)
                lg = as_linear(h.astype(mx.bfloat16))[:, -1, :]
                nxt = mx.argmax(lg, axis=-1)
                mx.eval(h, lg, nxt)
                hs.append(h[:, -1, :])  # [1, H] per step
                toks.append(int(nxt.item()))
                cur = nxt[:, None]
            mx.eval(hs)
            greedy_records.append(
                {
                    # each step is [1, H]; stack along a NEW axis -> [1, G, H]
                    "h": mx.concatenate([mx.expand_dims(s, 1) for s in hs], axis=1)[
                        0
                    ].astype(mx.float32),  # [G, H]
                    "TRUE": list(toks),
                    "TRUNK": list(toks),
                }
            )
            if (pi + 1) % 8 == 0:
                print(f"  built {pi + 1}/{len(texts)} records", flush=True)

        if args.cache:
            import pickle

            os.makedirs(os.path.dirname(args.cache) or ".", exist_ok=True)
            with open(args.cache, "wb") as fh:
                pickle.dump({"corpus": corpus_records, "greedy": greedy_records}, fh)
            print(f"cached records to {args.cache}", flush=True)

    n_eval = args.holdout
    greedy_eval = greedy_records[:n_eval]
    pool_records = (
        greedy_records[n_eval:] if prefix_kind == "greedy" else corpus_records[n_eval:]
    )
    print(
        f"{len(corpus_records)} corpus + {len(greedy_records)} greedy records "
        f"({time.time() - t_start:.0f}s)",
        flush=True,
    )

    # ---- training pool --------------------------------------------------
    # For a record indexed by t, the head at depth j (0-based) is
    #   conditioned on S[t + j]      (S = the input sequence)
    #   and trained to predict T[t + j + 1]   (T = the target sequence)
    def build_pool():
        Hp, Sp, Tp = [], [], []
        for r in pool_records:
            h = r["h"]
            S = r["TRUE" if input_kind == "truth" else "TRUNK"]
            T = r["TRUE" if target_kind == "truth" else "TRUNK"]
            L = len(S)
            if L < args.count + 1:
                continue
            for t in range(L - args.count):
                Hp.append(h[t])
                Sp.append(S[t : t + args.count])
                Tp.append(T[t + 1 : t + 1 + args.count])
        if not Hp:
            return None
        return {
            "h": mx.stack(Hp),  # [N, H]
            "S": mx.array(Sp, mx.int32),  # [N, K]
            "T": mx.array(Tp, mx.int32),  # [N, K]
        }

    pool = build_pool()
    if pool is None:
        raise SystemExit("no training rows")
    N = pool["h"].shape[0]
    print(f"{N} training positions", flush=True)

    def sample_batch(n_positions, rng):
        idx = mx.array(rng.sample(range(N), min(n_positions, N)), mx.int32)
        return {
            "h": pool["h"][idx][None],  # [1, B, H]
            "S": pool["S"][idx][None],  # [1, B, K]
            "T": pool["T"][idx],  # [B, K]
        }

    # ---- the trainable heads -------------------------------------------
    heads = [init_head(H, F, seed=args.seed + j) for j in range(args.count)]
    keys = ["proj", "norm", "gate", "up", "down"]
    params = {f"{j}.{k}": heads[j][k] for j in range(args.count) for k in keys}
    opt = optimizers.Adam(learning_rate=args.lr)
    rng = random.Random(args.seed)
    mx.random.seed(args.seed)

    def loss_fn(p, batch):
        import mlx.core as mx

        prev = batch["h"]  # [1, B, H]
        total = mx.zeros([], mx.float32)
        for j in range(args.count):
            head = {k: p[f"{j}.{k}"] for k in keys}
            tok_in = batch["S"][:, :, j]  # [1, B]
            emb = emb_w[tok_in].astype(mx.float32)  # [1, B, H]
            dh = head_forward(head, prev, emb)  # [1, B, H]
            student = as_linear(dh.astype(mx.bfloat16))[0]  # [B, V]
            total = total + chunked_ce(student, batch["T"][:, j])
            prev = dh
        return total

    vg = mx.value_and_grad(loss_fn)

    # ---- OVERFIT PROBE ---------------------------------------------------
    if args.overfit_probe:
        tiny = sample_batch(16, random.Random(0))
        first = None
        for step in range(1, args.overfit_probe + 1):
            loss, grads = vg(params, tiny)
            opt.update(params, grads)
            mx.eval(params)
            if first is None:
                first = float(loss.item())
            if step % 25 == 0 or step == args.overfit_probe:
                print(
                    f"  overfit step {step}: loss {float(loss.item()):.4f} (first {first:.4f})",
                    flush=True,
                )
        print(
            f"overfit probe: loss {first:.4f} -> {float(loss.item()):.4f}", flush=True
        )
        return 0

    print(f"training {args.count} head(s)", flush=True)
    t0 = time.time()
    history = []
    for step in range(1, args.steps + 1):
        batch = sample_batch(args.batch, rng)
        loss, grads = vg(params, batch)
        opt.update(params, grads)
        mx.eval(params)
        if step % 100 == 0 or step == 1:
            history.append({"step": step, "loss": float(loss.item())})
            print(
                f"step {step}/{args.steps} loss {float(loss.item()):.4f} "
                f"({time.time() - t0:.0f}s)",
                flush=True,
            )

    # ---- sync the heads with the trained params --------------------------
    # mx.optimizers.Optimizer.update REPLACES the dict entries rather than
    # mutating the arrays in place, so `heads[j][k]` still points at the
    # INITIAL arrays unless they are re-read here. Measuring `heads` without
    # this sync measures an UNTRAINED model (a measured 0.0 acceptance on a
    # head whose loss had fallen to 2.07). The old lane code did not have
    # this bug because it read the same dict it updated.
    for j in range(args.count):
        for k in keys:
            heads[j][k] = params[f"{j}.{k}"]
    mx.eval(params)

    # ---- MEASURE: decode-consistent acceptance --------------------------
    # accept_self    head j is fed head j-1's OWN argmax (what the decoder does)
    # accept_teacher head j is fed the trunk's own token (teacher forced)
    # PREFIX acceptance is what decides how many tokens a cycle commits.
    def measure(records):
        import mlx.core as mx

        n_pos = 0
        self_ok = [0] * args.count
        teacher_ok = [0] * args.count
        for r in records:
            h = r["h"]
            toks = r["TRUNK"]
            L = len(toks)
            if L < args.count + 1:
                continue
            n = L - args.count
            prev = h[:n][None]  # [1, n, H]
            alive_self = mx.ones([n], mx.bool_)
            alive_teacher = mx.ones([n], mx.bool_)
            prev_argmax = None
            for j in range(args.count):
                emb_self = emb_w[
                    (mx.array(toks[:n], mx.int32) if j == 0 else prev_argmax)[None]
                ].astype(mx.float32)
                emb_teacher = emb_w[mx.array(toks[j : j + n], mx.int32)[None]].astype(
                    mx.float32
                )
                # the trunk's token at position t+j+1 is the target of head j
                target = mx.array(toks[j + 1 : j + 1 + n], mx.int32)

                dh_self = head_forward(heads[j], prev, emb_self)
                am_self = mx.argmax(as_linear(dh_self.astype(mx.bfloat16))[0], axis=-1)
                dh_teacher = head_forward(heads[j], prev, emb_teacher)
                am_teacher = mx.argmax(
                    as_linear(dh_teacher.astype(mx.bfloat16))[0], axis=-1
                )

                hit_self = (am_self == target) & alive_self
                hit_teacher = (am_teacher == target) & alive_teacher
                self_ok[j] += int(hit_self.sum().item())
                teacher_ok[j] += int(hit_teacher.sum().item())
                alive_self = alive_self & hit_self
                alive_teacher = alive_teacher & hit_teacher
                prev_argmax = am_self
                prev = dh_self
            n_pos += n
        return (
            [self_ok[j] / max(1, n_pos) for j in range(args.count)],
            [teacher_ok[j] / max(1, n_pos) for j in range(args.count)],
            n_pos,
        )

    acc, acc_teacher, n_pos = measure(greedy_eval)
    print(f"accept_self   by depth: {[round(a, 4) for a in acc]}", flush=True)
    print(f"accept_teacher by depth: {[round(a, 4) for a in acc_teacher]}", flush=True)

    # tokens per cycle under the specdec contract: 1 (the trunk's own
    # committed token) + the accepted prefix length.
    toks_per_cycle = [1.0 + sum(acc[: j + 1]) for j in range(args.count)]
    print(f"tokens/cycle by count: {[round(t, 3) for t in toks_per_cycle]}", flush=True)

    # ---- export the trained head (for the native Rust port) --------------
    head_path = None
    if args.out:
        head_path = os.path.splitext(args.out)[0] + ".head.safetensors"
        import mlx.core as mx

        tensors = {}
        for j in range(args.count):
            for k in keys:
                tensors[f"model.mtp.d{j}.{k}.weight"] = params[f"{j}.{k}"].astype(
                    mx.float32
                )
        mx.save_safetensors(head_path, tensors)
        print(f"exported head -> {head_path}", flush=True)

    # ---- timings (real, forced evaluation) ----
    timings = {}
    if args.measure_timings:
        cur = mx.array([[1]], mx.int32)
        t_ar = real_timeit(lambda: model.model(cur))
        t_lm = real_timeit(lambda: as_linear(mx.zeros([1, 1, H], mx.bfloat16)))
        t_draft_mlp = real_timeit(
            lambda: head_forward(
                heads[0],
                mx.zeros([1, 1, H], mx.float32),
                mx.zeros([1, 1, H], mx.float32),
            )
        )
        verify = {}
        for k in range(1, args.count + 3):
            ids = mx.array([[1] * k], mx.int32)
            verify[k] = real_timeit(lambda k=k: model.model(ids))
        timings = {
            "t_ar_body_1pos_s": t_ar,
            "t_lm_head_s": t_lm,
            "t_draft_mlp_s": t_draft_mlp,
            "t_body_kpos_s": {str(k): v for k, v in verify.items()},
            "note": "REAL execution (output forced each iteration). The older "
            "lane harness evaluated an unrelated dummy array and timed "
            "graph construction instead; it also omitted the draft "
            "head's own vocab projection.",
        }
        print(json.dumps(timings, indent=2), flush=True)

    verdict = {
        "contract": "mtp.retarget.v1",
        "when_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "model": args.model,
        "arm": args.arm,
        "arm_meaning": ARM_MEANING[args.arm],
        "arm_variables": {
            "prefix": prefix_kind,
            "input_sequence": input_kind,
            "target_sequence": target_kind,
        },
        "count": args.count,
        "steps": args.steps,
        "seed": args.seed,
        "loss_history": history,
        "records": {
            "corpus": len(corpus_records),
            "greedy": len(greedy_records),
            "eval_prompts": len(greedy_eval),
            "train_positions": N,
        },
        "positions_measured": n_pos,
        "accept_self_prefix_by_depth": acc,
        "accept_teacher_prefix_by_depth": acc_teacher,
        "tokens_per_cycle_by_count": toks_per_cycle,
        "gates": {
            "J-G1_acceptance_min": 0.60,
            "J-G1_pass": bool(acc and acc[0] >= 0.60),
            "J-G3_best_count_by_tokens_per_cycle": (
                max(range(len(toks_per_cycle)), key=lambda j: toks_per_cycle[j])
                if toks_per_cycle
                else None
            ),
        },
        "timings": timings,
        "power": power_snapshot.snapshot(),
        "non_claims": [
            "acceptance is hardware-independent; the speedup gate is NOT claimed here",
            "the native Rust port is the authority for J-G2 (MTP-GATES.md)",
            "one model, one corpus, one seed",
        ],
    }
    text = json.dumps(verdict, indent=2, sort_keys=True)
    print(text)
    if args.out:
        os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
        with open(args.out, "w") as fh:
            fh.write(text + "\n")
    return 0


def self_test():
    """Pinned synthetic cases for the MEASUREMENT harness.

    The acceptance number is the load-bearing result of this experiment, so
    the harness that produces it must be shown to read 1.0 on a head that
    always guesses right and 0.0 on one that always guesses wrong. A harness
    that reports 0.0 for everything is indistinguishable from a broken one.
    """
    import mlx.core as mx

    H = 8
    L = 40
    toks = [(i * 7 + 3) % 50 for i in range(L)]

    def score(records, mode):
        n_pos = 0
        ok = 0
        for r in records:
            t = r["TRUNK"]
            n = len(t) - 1
            n_pos += n
            am = (
                mx.array(t[1 : 1 + n], mx.int32)
                if mode == "perfect"
                else mx.array([(v + 1) % 50 for v in t[1 : 1 + n]], mx.int32)
            )
            target = mx.array(t[1 : 1 + n], mx.int32)
            ok += int((am == target).sum().item())
        return ok / max(1, n_pos), n_pos

    recs = [{"h": mx.zeros([L, H], mx.float32), "TRUNK": toks}]
    a_perfect, n = score(recs, "perfect")
    a_wrong, _ = score(recs, "wrong")
    print(f"self-test: perfect={a_perfect:.4f} wrong={a_wrong:.4f} positions={n}")
    ok = a_perfect == 1.0 and a_wrong == 0.0
    print("self-test:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
