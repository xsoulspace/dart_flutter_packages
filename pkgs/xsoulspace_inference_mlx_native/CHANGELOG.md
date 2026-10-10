# Changelog

## 0.1.1 (2026-10-11)

Engine change only — no Dart API change (ADR 0054 R6).

- **LFM2/LFM2.5 forward is now a declared plan, and it is the DEFAULT
  path.** The hybrid short-conv/GQA forward rides the composition API's
  plan executor and binding table like laya and Qwen3 already did
  (`LAYA_LFM2_PLAN=0` reverts to the imperative walk for A/B). Attention
  KV buffers and the sliding conv state are functional plan outputs.
- New bit-parity gates `tests/lfm2_plan_parity.rs`: decode-step logits and
  prefill caches (KV + conv states, growth boundary crossed) are
  bit-identical between the plan and imperative paths; the fixture battery
  (64/64 vs the mlx-lm reference, the 700M v1-config row, the opt-in EOS
  gate) passes under both routing modes. Measured on AC: 64/64 tokens at
  64.8 tok/s through the plan (imperative reference: 49–53).
- New executor-transparency sweep `tests/plan_op_sweep.rs`: 23 op cells
  bit-identical between direct binding dispatch and the plan executor.
- `LAYA_COMPILE` default-flip DECLINED with evidence (first traced call per
  shape costs seconds; break-even 150+ decisions/shape) — stays opt-in.
- Recorded serving non-claims: no cross-request KV prefix reuse, no token
  streaming.
