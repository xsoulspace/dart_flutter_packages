# PORTING-MOE.md — the banked MoE-port contract (from Line B, 2026-10-18)

Line B (SSD-paged Qwen3-30B-A3B-4bit, `bench/stage1_paged_moe/`) proved the
engineering and failed the physics; what it banked for any future MoE port
into this crate is the router-precision contract below. It exists because a
parity gate failed at block 47 of 48 and the root cause was worth a law.

## The fp16-router-scale pin

**Routers compute in fp32 end-to-end, from dequantized weights.** The
Qwen3-30B checkpoint stores its router quantized like any other weight; the
Python reference dequantizes routers once at load and runs the routing
matmul in fp32 (`_router_fp32`), and the paged forward shares that exact
fp32 routing math with the reference. Do not let a port compute routing in
fp16.

Why (measured, block-47 lesson): Qwen3 routing logits are noise-thin —
top-8/top-9 logit gaps of 1e-3…3e-2 — while the residual stream grows to
~1.1e3 by mid-network. fp16-vs-fp32 rounding at that scale flips routes at
quantization-noise probability; on the real 30B this showed up as rel
hidden-state error 3.9e-3 at the last block where earlier blocks sat at
~1.6e-4, and 364/384 apparent "routing flips" traced to exactly this
boundary (hidden-state divergence against hair-thin gaps), not to a layout
bug.

## Consequences for any port / fixture

1. **Router weights dequantize at load, fp32 resident** (they are tiny —
   [hidden, experts]); routing matmul, softmax/top-k, and the renormalize
   all stay fp32. Only expert compute narrows to fp16.
2. **Parity fixtures pin routes, not just logits.** A fixture must record
   the per-layer expert sets on fixed inputs, so a precision-induced route
   flip cannot hide inside a small logit delta. Route equality is part of
   the parity gate.
3. **Measure the margin before trusting any routing-precision choice**:
   the top-k gap distribution on the target checkpoint decides whether fp16
   anywhere near the router is defensible. The 30B measurement says it is
   not.
4. **Trained routers (Line I) must be born noise-stable** — fp32 router +
   margin loss (TRAIN-GATES.md context) — so the same trap never opens for
   our own checkpoints. The parity pin then holds by construction.
5. **Segment stores ride the shared contract** (content-addressed packed
   segments, offset point reads, digest-verified loads — the
   `nursery` module is the in-crate reader; `bench/stage1_paged_moe/
   segment_store.py` is the pack-time reference). A wrong segment digest is
   a hard error, never a silent zero.

Status: no MoE forward exists in this crate (Line B failed the ≥15 tok/s
physics gate on this hardware — 16.3 GB expert payload > ~10 GB usable RAM;
see `bench/stage1_paged_moe/RESULTS.md`). This file is the contract the
port must satisfy when a bytes/token-qualified checkpoint justifies one.
