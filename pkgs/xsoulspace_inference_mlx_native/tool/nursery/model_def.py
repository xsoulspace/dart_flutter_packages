"""The RUNG-0 drosophila model — the ONE definition both implementations mirror.

`native/mlx_native/src/nursery_model.rs` is the runtime side of this exact
contract (same tensor names, same recurrence, same top-k tie rule, same
label order). Nothing here may change without naming the Rust mirror in the
same edit.

Shape of the model (TRAIN-GATES.md rung 0, 1–5M params):

  byte-level vocab  V = 256 bytes + BOS(256) + EOS(257)
  per block:  x += Wo·attn(rms(x))            carry-state linear attention
              x += MoE(rms(x))                router -> top-k experts
  linear attention (read-then-update, strictly causal):
      y_t = q_t · S_{t-1}                     (BOS sees the empty state)
      S_t = decay * S_{t-1} + outer(k_t, v_t) (decay per channel, sigmoid)
  MoE: logits = h @ Wr^T (fp32 — the PORTING-MOE law); top-k by value,
  ties to the LOWER expert index; gate weights = softmax(selected logits);
  expert = down( silu(gate(h)) * up(h) ).

Tensor names (pack_at_birth.py role rules must classify these):
  model.embed_tokens.weight            embed  [V, H]
  model.norm.weight                    norm   [H]
  model.lm_head.weight                 head   [V, H]
  model.label_head.weight              dense  [n_kinds, H]   (GATE-3 behavior)
  model.layers.{l}.input_layernorm.weight          norm  [H]
  model.layers.{l}.self_attn.{q,k,v,o}_proj.weight dense [H, H]
  model.layers.{l}.self_attn.decay.weight          dense [H]  (sigmoid at runtime)
  model.layers.{l}.post_attention_layernorm.weight norm  [H]
  model.layers.{l}.mlp.gate.weight                router [E, H]  fp32 BY LAW
  model.layers.{l}.mlp.experts.{e}.{gate,up,down}_proj.weight  expert

Losses (the differentiable nudges; GATE-2's hard set persistence is measured
from exported traces, never assumed from a loss):
  total = ce(lm) + lam_label*ce(label) + lam_margin*margin_hinge
          + lam_route*route_smoothness
  margin_hinge     = mean(relu(margin_target - (top1_logit - top2_logit)))
  route_smoothness = mean(1 - cos(router_logits_t, router_logits_{t-1}))

Honest limits: the sequential recurrence is clarity-first (a drosophila does
not need a parallel scan); rung-0 saves unquantized f32, so the GATE-4
bytes/token for this rung is the honest upper bound of the format.
"""

import hashlib
import json

BOS = 256
EOS = 257
VOCAB = 258

LABEL_KINDS = ["open", "done", "action", "fact"]


class NurseryConfig:
    """config.json — the same keys the fixture (pack_fixture.py) and
    pack_at_birth payload_stats read: num_experts, num_experts_per_tok,
    moe_intermediate_size, hidden_size, vocab_size, num_hidden_layers."""

    def __init__(self, hidden_size=128, layers=4, experts=8, topk=2,
                 intermediate=256, vocab_size=VOCAB, rms_norm_eps=1e-5,
                 router_margin_target=1.0,
                 lam_label=1.0, lam_margin=0.1, lam_route=0.05,
                 max_seq_len=512, routing_window=1,
                 label_kinds=None, seed=0, **extra):
        self.hidden_size = hidden_size
        self.layers = layers
        self.experts = experts
        self.topk = topk
        self.intermediate = intermediate
        self.vocab_size = vocab_size
        self.rms_norm_eps = rms_norm_eps
        self.router_margin_target = router_margin_target
        self.lam_label = lam_label
        self.lam_margin = lam_margin
        self.lam_route = lam_route
        self.max_seq_len = max_seq_len
        # The A/B arm (FINDINGS §12–13): routing_window = W reuses one
        # expert SET for W consecutive positions (re-decided at each window
        # start). 1 = per-token routing, the default and the Rust mirror's
        # always-available path; W > 1 trades quality (GATE-1/3 measure the
        # cost) for persistence (GATE-2 measures the win).
        self.routing_window = max(1, int(routing_window))
        self.label_kinds = list(label_kinds or LABEL_KINDS)
        self.seed = seed
        self.extra = dict(extra)

    def to_json(self):
        d = {
            "model_type": "nursery",
            "hidden_size": self.hidden_size,
            "num_hidden_layers": self.layers,
            "num_experts": self.experts,
            "num_experts_per_tok": self.topk,
            "moe_intermediate_size": self.intermediate,
            "vocab_size": self.vocab_size,
            "rms_norm_eps": self.rms_norm_eps,
            "router_margin_target": self.router_margin_target,
            "lam_label": self.lam_label,
            "lam_margin": self.lam_margin,
            "lam_route": self.lam_route,
            "max_seq_len": self.max_seq_len,
            "routing_window": self.routing_window,
            "label_kinds": self.label_kinds,
            "seed": self.seed,
        }
        d.update(self.extra)
        return d

    @classmethod
    def from_json(cls, d):
        # Canonical config.json names -> constructor names. The canonical
        # keys are what pack_at_birth and the Rust loader read; silently
        # dumping them into **extra trained DEFAULTS while saving the
        # defaults back (self-consistent stores, silently-wrong intent).
        rename = {"num_hidden_layers": "layers",
                  "moe_intermediate_size": "intermediate",
                  "num_experts": "experts",
                  "num_experts_per_tok": "topk"}
        kwargs = {}
        for k, v in d.items():
            if k == "model_type":
                continue
            kwargs[rename.get(k, k)] = v
        unknown = set(kwargs) - set(cls.__init__.__code__.co_varnames)
        if unknown:
            raise SystemExit(f"unknown config keys (typo?): {sorted(unknown)}")
        return cls(**kwargs)


def param_names_and_shapes(cfg):
    """The full (name, shape, dtype) list in canonical order — the exact set
    a rung-0 checkpoint saves and the store addresses. Pure python:
    scale_decision.py and the Rust loader agree with this without mlx."""
    H, F, E, V = cfg.hidden_size, cfg.intermediate, cfg.experts, cfg.vocab_size
    out = [("model.embed_tokens.weight", [V, H], "float32"),
           ("model.norm.weight", [H], "float32"),
           ("model.lm_head.weight", [V, H], "float32"),
           ("model.label_head.weight", [len(cfg.label_kinds), H], "float32")]
    for l in range(cfg.layers):
        p = f"model.layers.{l}"
        out += [
            (f"{p}.input_layernorm.weight", [H], "float32"),
            (f"{p}.self_attn.q_proj.weight", [H, H], "float32"),
            (f"{p}.self_attn.k_proj.weight", [H, H], "float32"),
            (f"{p}.self_attn.v_proj.weight", [H, H], "float32"),
            (f"{p}.self_attn.o_proj.weight", [H, H], "float32"),
            (f"{p}.self_attn.decay.weight", [H], "float32"),
            (f"{p}.post_attention_layernorm.weight", [H], "float32"),
            (f"{p}.mlp.gate.weight", [E, H], "float32"),
        ]
        for e in range(E):
            out += [
                (f"{p}.mlp.experts.{e}.gate_proj.weight", [F, H], "float32"),
                (f"{p}.mlp.experts.{e}.up_proj.weight", [F, H], "float32"),
                (f"{p}.mlp.experts.{e}.down_proj.weight", [H, F], "float32"),
            ]
    return out


def param_count(cfg):
    n = 1
    total = 0
    for _, shape, _ in param_names_and_shapes(cfg):
        n = 1
        for d in shape:
            n *= d
        total += n
    return total


def encode_text(text, max_seq_len=512):
    """BOS + utf-8 bytes + EOS, truncated to max_seq_len total."""
    ids = [BOS] + list(text.encode("utf-8")) + [EOS]
    return ids[:max_seq_len]


def split_of(example_id, eval_every=10, eval_mod=9):
    """Deterministic train/eval split: sha256(id) % eval_every == eval_mod.
    Pinned so a re-run re-derives the same split without a side file."""
    h = hashlib.sha256(example_id.encode("utf-8")).hexdigest()
    return "eval" if int(h, 16) % eval_every == eval_mod else "train"


def top_k_experts(logits, k):
    """THE shared selection rule (Rust mirrors this exactly): k largest by
    value, ties to the LOWER index; returns the selected ids ASCENDING."""
    order = sorted(range(len(logits)), key=lambda i: (-logits[i], i))
    return sorted(order[:k])


def predicted_label(label_logits, cfg):
    """Deterministic argmax: highest value, ties to the lower kind index
    (the rule the Rust runtime mirrors)."""
    vals = [float(v) for v in label_logits]
    best = 0
    for i in range(1, len(vals)):
        if vals[i] > vals[best]:
            best = i
    return cfg.label_kinds[best]


# ---------------------------------------------------------------- mlx forward

def init_params(cfg):
    """Deterministic init from the config seed — re-running reproduces the
    same initial weights."""
    import mlx.core as mx

    mx.random.seed(cfg.seed)
    H, F = cfg.hidden_size, cfg.intermediate

    def normal(shape, scale):
        return (mx.random.normal(shape) * scale).astype(mx.float32)

    params = {}
    params["model.embed_tokens.weight"] = normal([cfg.vocab_size, H], 1.0 / H ** 0.5)
    params["model.norm.weight"] = mx.ones([H], mx.float32)
    params["model.lm_head.weight"] = normal([cfg.vocab_size, H], 1.0 / H ** 0.5)
    params["model.label_head.weight"] = normal(
        [len(cfg.label_kinds), H], 1.0 / H ** 0.5)
    for l in range(cfg.layers):
        p = f"model.layers.{l}"
        params[f"{p}.input_layernorm.weight"] = mx.ones([H], mx.float32)
        params[f"{p}.post_attention_layernorm.weight"] = mx.ones([H], mx.float32)
        for proj in ("q_proj", "k_proj", "v_proj", "o_proj"):
            params[f"{p}.self_attn.{proj}.weight"] = normal([H, H], 1.0 / H ** 0.5)
        # sigmoid(-1.0) ~ 0.27 — decays start in the "remember a few tokens"
        # region, not saturated at 0 or 1.
        params[f"{p}.self_attn.decay.weight"] = mx.full([H], -1.0, mx.float32)
        params[f"{p}.mlp.gate.weight"] = normal([cfg.experts, H], 1.0 / H ** 0.5)
        for e in range(cfg.experts):
            b = f"{p}.mlp.experts.{e}"
            params[f"{b}.gate_proj.weight"] = normal([F, H], 1.0 / H ** 0.5)
            params[f"{b}.up_proj.weight"] = normal([F, H], 1.0 / H ** 0.5)
            params[f"{b}.down_proj.weight"] = normal([H, F], 1.0 / F ** 0.5)
    return params


def rms_norm(x, weight, eps):
    import mlx.core as mx
    return mx.fast.rms_norm(x, weight, eps)


def cross_entropy_mean(logits, targets):
    """Stable manual CE over [N, C] logits and [N] int targets — no
    mx.losses import, one formula, easy to audit."""
    import mlx.core as mx
    a = logits - mx.max(logits, axis=-1, keepdims=True)
    logz = mx.log(mx.sum(mx.exp(a), axis=-1))
    picked = mx.take_along_axis(
        a, mx.reshape(targets, [-1, 1]), axis=-1).reshape([-1])
    return mx.mean(logz - picked)


def forward_sequence(params, cfg, tokens):
    """Teacher-forced forward over one sequence ([T] int ids).

    Returns:
      lm_logits     [T, V]    position t predicts token t+1
      label_logits  [n_kinds] from the final position's hidden state
      router_logits {layer: [T, E]} fp32 (margin + smoothness losses)
      routes        {layer: [T][k]} selected expert ids, ascending
      pole_values   {layer: [E]}    mean routing weight per expert over T

    The sequential recurrence IS the contract the Rust stepwise runtime
    mirrors (same read-then-update order, same tie rules).
    """
    import mlx.core as mx

    T = len(tokens)
    H, E, K = cfg.hidden_size, cfg.experts, cfg.topk
    ids = mx.array(tokens, mx.int32)
    x = params["model.embed_tokens.weight"][ids]          # [T, H]

    routes, pole_values, router_logits = {}, {}, {}
    for l in range(cfg.layers):
        p = f"model.layers.{l}"
        # ---- carry-state linear attention (read-then-update) ----
        h = rms_norm(x, params[f"{p}.input_layernorm.weight"], cfg.rms_norm_eps)
        q = h @ params[f"{p}.self_attn.q_proj.weight"].T   # [T, H]
        k = h @ params[f"{p}.self_attn.k_proj.weight"].T
        v = h @ params[f"{p}.self_attn.v_proj.weight"].T
        decay = mx.sigmoid(params[f"{p}.self_attn.decay.weight"])   # [H]
        ys = []
        state = mx.zeros([H, H], mx.float32)
        for t in range(T):
            ys.append((q[t] @ state).reshape(1, H))        # read S_{t-1}
            state = state * decay.reshape(1, H) + mx.outer(k[t], v[t])
        attn = mx.concatenate(ys, axis=0)                  # [T, H]
        x = x + attn @ params[f"{p}.self_attn.o_proj.weight"].T

        # ---- MoE block ----
        h2 = rms_norm(x, params[f"{p}.post_attention_layernorm.weight"],
                      cfg.rms_norm_eps)
        rlogits = (h2 @ params[f"{p}.mlp.gate.weight"].T).astype(mx.float32)
        router_logits[l] = rlogits
        rl = [row for row in rlogits.tolist()]
        sel_routes = []
        pole = [0.0] * E
        rows = []
        window = max(1, int(getattr(cfg, "routing_window", 1)))
        sel_window = None
        for t in range(T):
            if sel_window is None or t % window == 0:
                sel_window = top_k_experts(rl[t], K)
            sel = sel_window
            sel_routes.append(sel)
            # LIVE weights: take from the graph-carrying rlogits row so the
            # LM loss gradient reaches the router through the combine weights
            # (the python-float `rl` above is only the detached selection
            # view). wlist is the detached copy for pole bookkeeping.
            w = mx.softmax(rlogits[t][mx.array(sel, mx.int32)])
            wlist = [float(x) for x in w]
            acc = mx.zeros([H], mx.float32)
            hh = h2[t].reshape(1, H)
            for j, e in enumerate(sel):
                eb = f"{p}.mlp.experts.{e}"
                gate = hh @ params[f"{eb}.gate_proj.weight"].T
                # silu = x * sigmoid(x) (this mlx build has no mx.silu; the
                # Rust mirror composes the identical two ops).
                g = gate * mx.sigmoid(gate)
                u = hh @ params[f"{eb}.up_proj.weight"].T
                d = (g * u) @ params[f"{eb}.down_proj.weight"].T
                acc = acc + w[j] * d.reshape(H)
                pole[e] += wlist[j]
            rows.append(acc.reshape(1, H))
        moe = mx.concatenate(rows, axis=0)                 # [T, H]
        routes[l] = sel_routes
        pole_values[l] = [v / T for v in pole]
        x = x + moe

    final = rms_norm(x[-1], params["model.norm.weight"], cfg.rms_norm_eps)
    hidden_all = rms_norm(x, params["model.norm.weight"], cfg.rms_norm_eps)
    return {
        "lm_logits": hidden_all @ params["model.lm_head.weight"].T,
        "label_logits": final @ params["model.label_head.weight"].T,
        "router_logits": router_logits,
        "routes": routes,
        "pole_values": pole_values,
        "final_hidden": final,
        # Additive eval-side view ([T, H] normalized states) — slot heads
        # with pooled readouts read this; the recurrence the Rust runtime
        # mirrors is unchanged.
        "hidden_all": hidden_all,
    }


def losses(params, cfg, tokens, label_id):
    """All loss terms for one example. Returns (total mx scalar, parts dict
    of python floats for logging)."""
    import mlx.core as mx

    out = forward_sequence(params, cfg, tokens)
    ce = cross_entropy_mean(out["lm_logits"][:-1], mx.array(tokens[1:], mx.int32))
    label_ce = cross_entropy_mean(
        out["label_logits"].reshape([1, len(cfg.label_kinds)]),
        mx.array([label_id], mx.int32))

    margins, smooths = [], []
    for l in range(cfg.layers):
        rl = out["router_logits"][l]                      # [T, E] fp32
        if cfg.experts >= 2:
            sorted_desc = mx.sort(rl, axis=-1)[:, -2:]    # top-2, ascending
            margins.append(relu(
                cfg.router_margin_target - (sorted_desc[:, 1] - sorted_desc[:, 0])))
        if rl.shape[0] >= 2:
            a, b = rl[1:], rl[:-1]
            cos = mx.sum(a * b, axis=-1) / (
                mx.sqrt(mx.sum(a * a, axis=-1))
                * mx.sqrt(mx.sum(b * b, axis=-1)) + 1e-8)
            smooths.append(1.0 - cos)
    # dense (E=1) has no top-2 gap: the margin term is vacuously zero
    margin = (mx.mean(mx.concatenate(margins, axis=0)) if margins
              else mx.zeros([], mx.float32))
    smoothness = mx.mean(mx.concatenate(smooths, axis=0))

    total = ce + cfg.lam_label * label_ce + cfg.lam_margin * margin \
        + cfg.lam_route * smoothness
    parts = {"ce": float(ce.item()), "label_ce": float(label_ce.item()),
             "margin": float(margin.item()),
             "smoothness": float(smoothness.item())}
    return total, parts


def relu(x):
    import mlx.core as mx
    return mx.maximum(x, mx.zeros_like(x))


def topk_ids_vec(logits, k):
    """Vectorized top_k_experts — THE contract: k largest by value, ties to
    the LOWER index, ids ASCENDING. logits [..., E] -> int ids [..., k].
    mlx argmax returns the FIRST maximum (numpy semantics); the exact-tie
    cases in train_parity_smoke.py pin this — the fast path may not train
    if that pin fails."""
    import mlx.core as mx
    E = logits.shape[-1]
    eye = mx.eye(E)
    remaining = logits
    ids = []
    for _ in range(k):
        idx = mx.argmax(remaining, axis=-1)
        ids.append(idx)
        taken = eye[idx]  # [..., E] one-hot of the taken index
        remaining = mx.where(taken > 0, mx.array(-1e30, logits.dtype),
                             remaining)
    return mx.sort(mx.stack(ids, axis=-1), axis=-1)


def forward_sequence_fast(params, cfg, tokens, lengths, chunk=32):
    """Batched + chunked TRAINING forward (the fast path; the pinned
    definition stays forward_sequence — decode/eval/Rust parity never
    changes).

    tokens [B, T] int, right-padded with EOS; lengths [B] real counts.
    Mathematically the SAME model: read-then-update recurrence
    (y_t = q_t · S_{t-1}; S_t = decay ⊙ S_{t-1} + k_t v_t^T, decay on the
    v-dimension), fp32 router, THE top-k contract, softmax combine.
    Float ASSOCIATION differs (chunk-parallel decay powers, batched matmuls)
    — that is exactly what train_parity_smoke.py pins: routes exact on
    margin-carrying weights, logits <= 1e-2.

    Returns lm_logits [B,T,V], label_logits [B,nk], routes [B,L,T,k],
    router_logits {layer: [B,T,E] fp32}.
    """
    import mlx.core as mx

    B, T = tokens.shape
    H, E, K = cfg.hidden_size, cfg.experts, cfg.topk
    x = params["model.embed_tokens.weight"][tokens]  # [B,T,H]
    routes = []
    router_logits = {}
    n_chunks = (T + chunk - 1) // chunk
    j_idx = None
    for l in range(cfg.layers):
        p = f"model.layers.{l}"
        h = rms_norm(x, params[f"{p}.input_layernorm.weight"], cfg.rms_norm_eps)
        q = h @ params[f"{p}.self_attn.q_proj.weight"].T   # [B,T,H]
        k = h @ params[f"{p}.self_attn.k_proj.weight"].T
        v = h @ params[f"{p}.self_attn.v_proj.weight"].T
        decay = mx.sigmoid(params[f"{p}.self_attn.decay.weight"])  # [H]
        u = mx.log(decay)  # log-space: powers without underflow
        state = mx.zeros([B, H, H], mx.float32)
        ys = []
        for c in range(n_chunks):
            lo, hi = c * chunk, min(T, (c + 1) * chunk)
            C = hi - lo
            qc, kc, vc = q[:, lo:hi], k[:, lo:hi], v[:, lo:hi]  # [B,C,H]
            if j_idx is None or j_idx.shape[0] < C:
                j_idx = mx.arange(C)
            ji = j_idx[:C]  # within-chunk position, 0-based
            # intra-chunk: y_i = sum_{j<i} (q_i·k_j) decay^{i-1-j} v_j
            #   = exp((i-1)u) * sum_{j<i} (q_i·k_j) exp(-j u) v_j
            scores = qc @ mx.transpose(kc, (0, 2, 1))        # [B,C,C]
            strict = ji[None, :] < ji[:, None]               # j < i
            scores = mx.where(strict[None, :, :], scores,
                              mx.zeros_like(scores))
            Vexp = vc * mx.exp((-ji[:, None] * u[None, :])[None, :, :])
            Z = scores @ Vexp                                # [B,C,H]
            y_intra = Z * mx.exp(((ji - 1)[:, None] * u[None, :])[None, :, :])
            # carry: y_i = (q_i @ S_carry) * decay^i
            y_carry = (qc @ state) * mx.exp((ji[:, None] * u[None, :])[None, :, :])
            ys.append(y_carry + y_intra)
            # state update: S = decay^C S + sum_j k_j (decay^{C-1-j} v_j)^T
            Vw = vc * mx.exp(((C - 1 - ji)[:, None] * u[None, :])[None, :, :])
            state = state * mx.exp(C * u)[None, None, :] \
                + mx.einsum("bch,bcv->bhv", kc, Vw)
        attn = mx.concatenate(ys, axis=1)                    # [B,T,H]
        x = x + attn @ params[f"{p}.self_attn.o_proj.weight"].T

        h2 = rms_norm(x, params[f"{p}.post_attention_layernorm.weight"],
                      cfg.rms_norm_eps)
        rl = (h2 @ params[f"{p}.mlp.gate.weight"].T).astype(mx.float32)
        router_logits[l] = rl
        sel = topk_ids_vec(rl, K)                            # [B,T,k]
        sel = mx.stop_gradient(sel)   # ids are indices: no VJP through them
        window = max(1, int(getattr(cfg, "routing_window", 1)))
        if window > 1:
            # The A/B arm (TRAIN-GATES.md): every position reads its
            # window-start decision, the stepwise forward_sequence
            # definition. A real position t always has a real window start
            # ((t//W)*W <= t < length), so pads never decide for real
            # tokens; pad-only windows are masked from every loss.
            starts = (mx.arange(T) // window) * window       # [T]
            sel = mx.take(sel, starts, axis=1)               # [B,T,k]
        routes.append(sel)
        N = B * T
        rows = rl.reshape(N, E)
        sflat = sel.reshape(N, K)
        picked = mx.take_along_axis(rows, sflat, axis=1)     # [N,K]
        w = mx.softmax(picked, axis=1)
        Wm = (mx.eye(E)[sflat] * w[:, :, None]).sum(axis=1)  # [N,E]
        X2 = h2.reshape(N, H)
        GW = mx.stack([params[f"{p}.mlp.experts.{e}.gate_proj.weight"].T
                       for e in range(E)])                   # [E,H,F]
        UW = mx.stack([params[f"{p}.mlp.experts.{e}.up_proj.weight"].T
                       for e in range(E)])                   # [E,H,F]
        DW = mx.stack([params[f"{p}.mlp.experts.{e}.down_proj.weight"].T
                       for e in range(E)])                   # [E,F,H]
        G = (X2[None] @ GW)                                  # [E,N,F]
        U = (X2[None] @ UW)
        Hm = G * (mx.sigmoid(G) * U)                         # silu(g)*u
        Yd = Hm @ DW                                         # [E,N,H]
        moe = mx.einsum("enf,ne->nf", Yd, Wm).reshape(B, T, H)
        x = x + moe

    final = rms_norm(x, params["model.norm.weight"], cfg.rms_norm_eps)
    last = mx.take_along_axis(
        final, mx.reshape(lengths - 1, [B, 1, 1]), axis=1)   # [B,1,H]
    return {
        "lm_logits": final @ params["model.lm_head.weight"].T,
        "label_logits": (last[:, 0, :]
                         @ params["model.label_head.weight"].T),
        "routes": mx.stack(routes, axis=1),                  # [B,L,T,k]
        "router_logits": router_logits,
        # Normalized residual stream at every position ([B,T,H]); slot-level
        # heads (perm_gate_1) and the GATE-1 v2 residual probe read the last
        # real position from this — additive, the parity pins do not read it.
        "final_hidden": final,
    }


def losses_fast(params, cfg, tokens, lengths, label_ids):
    """Batched loss for the fast path — same four terms and the same
    masked means the stepwise losses() defines per example. Returns
    (total mx scalar, parts dict of floats)."""
    import mlx.core as mx

    out = forward_sequence_fast(params, cfg, tokens, lengths)
    B, T = tokens.shape
    pos = mx.arange(T)
    mask = pos[None, :] < mx.reshape(lengths, [B, 1])        # [B,T]

    # LM CE on real target positions (t predicts t+1)
    logits = out["lm_logits"][:, :-1]                        # [B,T-1,V]
    targets = tokens[:, 1:]
    m = mask[:, 1:]
    a = logits - mx.max(logits, axis=-1, keepdims=True)
    logz = mx.log(mx.sum(mx.exp(a), axis=-1))
    picked = mx.take_along_axis(
        a, mx.reshape(targets, [B, T - 1, 1]), axis=-1)[:, :, 0]
    # CE = logz - a[target] (the stepwise cross_entropy_mean formula; a
    # + sign here silently made the loss reward confident wrong picks)
    ce = mx.sum((logz - picked) * m) / mx.sum(m)

    label_ce = cross_entropy_mean(out["label_logits"],
                                  mx.reshape(label_ids, [B]))

    margins, smooths = [], []
    n_real = mx.sum(mask)
    n_pairs = mx.sum(mask[:, 1:])
    for l in range(cfg.layers):
        rl = out["router_logits"][l]                         # [B,T,E] fp32
        if cfg.experts >= 2:
            top2 = mx.sort(rl, axis=-1)[:, :, -2:]           # ascending
            gap = top2[:, :, 1] - top2[:, :, 0]
            margins.append(relu(cfg.router_margin_target - gap) * mask)
        if T >= 2:
            a_, b_ = rl[:, 1:], rl[:, :-1]
            cos = mx.sum(a_ * b_, axis=-1) / (
                mx.sqrt(mx.sum(a_ * a_, axis=-1))
                * mx.sqrt(mx.sum(b_ * b_, axis=-1)) + 1e-8)
            smooths.append((1.0 - cos) * mask[:, 1:])
    # masked means over ALL layers' real positions — the same quantity the
    # stepwise losses() means per example (pads contribute 0 to both sums);
    # dense (E=1) has no top-2 gap: the margin term is vacuously zero
    margin = (mx.sum(mx.concatenate([mx.reshape(mv, [-1]) for mv in margins]))
              / (n_real * cfg.layers) if margins
              else mx.zeros([], mx.float32))
    smoothness = mx.sum(mx.concatenate([mx.reshape(sv, [-1]) for sv in smooths])) \
        / (n_pairs * cfg.layers)

    total = ce + cfg.lam_label * label_ce + cfg.lam_margin * margin \
        + cfg.lam_route * smoothness
    parts = {"ce": float(ce.item()), "label_ce": float(label_ce.item()),
             "margin": float(margin.item()),
             "smoothness": float(smoothness.item())}
    return total, parts


def save_checkpoint(params, cfg, checkpoint_dir):
    """Save config.json + model.safetensors (f32), pack_at_birth-ready.
    Runge-0 saves unquantized f32 — the GATE-4 number for this rung is the
    honest upper bound of the format."""
    import os
    import mlx.core as mx
    import numpy as np
    import safetensors.numpy

    os.makedirs(checkpoint_dir, exist_ok=True)
    # mlx arrays expose the numpy protocol (np.asarray); this build has no
    # mx.to_numpy.
    arrays = {name: np.asarray(mx.astype(w, mx.float32), dtype=np.float32)
              for name, w in params.items()}
    safetensors.numpy.save_file(
        arrays, os.path.join(checkpoint_dir, "model.safetensors"))
    with open(os.path.join(checkpoint_dir, "config.json"), "w") as fh:
        json.dump(cfg.to_json(), fh, indent=2, sort_keys=True)
