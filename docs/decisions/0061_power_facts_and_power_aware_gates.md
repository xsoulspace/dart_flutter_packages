# ADR 0061: Power facts and power-aware gates — sense, record, gate, route; never command

Date: 2026-10-11
Status: Accepted and implemented (2026-10-11)
Related: 0051 (the power-state recording law, battery throttles 4–10×),
0054 (the composition API and its perf gates), 0060 (the first
power-contaminated gate red, recorded and never weakened)

## Context

macOS on battery throttles sustained GPU **and** CPU work 4–10× (ADR 0051
L3: decode 45→3.5 tok/s; chat template 68→1927 ms). The repo's response so
far is a manual law — every benchmark records the power state (`pmset -g
ps`) — and it has now failed twice in the same way: the AC-calibrated `l0`
dispatch gate went red on a mid-run unplug (ADR 0060's evidence note, then
again 2026-10-11). Each red cost an investigation and ended in "power-state
contaminated, not a code failure, never weakened."

The physical fact that frames everything: **Apple Silicon exposes no
user-space control over GPU clocks, power limits, or the sustained-load
throttle.** There is no `nvidia-smi -pl` equivalent; DVFS is firmware + OS
policy, and the battery cap exists to keep current draw within what the
cells can deliver. `caffeinate` blocks sleep, not throttling — folklore to
retire in writing. What IS available is complete *visibility* (power
source, charge, the OS's own `CPU_Speed_Limit`), and full control of our
side of the ceiling: what we measure, what our gates assert, where work
routes, and how many joules each forward costs.

## Decision

**Power is a runtime capability fact, in the same shape as `chip`** —
sensed, recorded, gated on, routed by. Never commanded.

1. **Sense: `power::facts()` (Rust) and `PowerFacts` (Dart).** One minimal
   shape, read fresh on every call (an unplug mid-run is exactly the event
   we care about — caching would hide it): `{source: ac|battery|unknown,
   batteryPercent: int?, cpuSpeedLimitPercent: int?}`. Parsed from `pmset
   -g ps` (source, percent) and `pmset -g therm` (`CPU_Speed_Limit`);
   sensor failure degrades to `unknown`, never fails the caller.
   `cpuSpeedLimitPercent < 100` is the OS's own throttle confession.
2. **Gate: perf gates assert ONLY on AC.** On battery (or throttled), a
   perf gate runs, prints its measurement plus a loud
   `POWER-CONTAMINATED — non-baseline (ADR 0061)` banner, and passes. On
   AC the assertion is byte-for-byte today's oracle — unchanged, teeth
   intact. `unknown` keeps asserting (status quo; no silent weakening —
   and a Metal-capable machine without `pmset` is not a machine we run
   on). **Bit/parity gates are NEVER power-conditioned** — they compare
   storage bits and are power-independent; conditioning them would be a
   real weakening.
3. **Record: the annotation IS the record.** A battery run's output line
   carries the facts (source, percent, limit) beside the measurement, so
   an agent reading the log never has to re-derive why a number looks
   slow. The manual `pmset` law becomes mechanical; nothing about it is
   removed.
4. **Route / pace / reduce-energy: recorded as consumers, not implemented
   here.** The afm `RoutedDecisionProvider` tiers local → mesh → remote
   from capability facts; power joins those facts when the throttle should
   move sustained lanes (2k–8k prefill, long decode) off the local host
   while laya's ~90 ms burst decisions stay local. Pacing tiers build on
   R5's chunked prefill. An energy-per-decision probe (IOReport Energy
   Model) is the missing measurement that would let rungs be judged in
   joules. Each is its own change with its own gates.

## Hard laws

- Never condition a bit/parity gate on power.
- Never retry a perf gate until the machine is on AC to make it pass —
  run honestly, annotate, and let the ADR carry the verdict.
- Power-fact failures degrade to `unknown`, never fail the caller; `l0`'s
  perf asserts hold on `unknown`.

## Non-claims

- **No power-control claim exists on Apple Silicon** (macOS or iOS): no
  API raises the ceiling; nothing here pretends to.
- Perf gates on battery detect **nothing** — an AC-only oracle is the
  deliberate trade; a regression visible only under throttle is recorded
  as noise by design.
- AC is not throttle-free forever (sustained load can still see thermal
  pressure); AC is the calibration point, not a guarantee.
- Battery level and age shift the cap — the same workload throttles
  differently at 20% vs 90%.
- iOS Low Power Mode cannot be opted out of, only detected.
- No energy measurements yet — IOReport is future work (consumer 4).
- The 6,608 ms first-traced-call figure (ADR 0054 R1 flip verdict) was
  measured on battery and is an upper bound; the verdict does not hinge
  on it.

## Consequences

- The twice-paid battery-unplug false red becomes a loud green annotation.
- Bench provenance is mechanical: every perf gate output self-describes
  its power state (the ADR 0051 law, enforced by the gates themselves).
- The Dart surface (`PowerFacts`) gives benches and future routing the
  same fact the Rust gates read — one fact, two consumers, one shape.
- Routing, pacing, and energy measurement remain open items with a named
  home (this ADR's consumer list), not implicit follow-ons.

## Evidence

All measured 2026-10-11, M1/16GiB.

- The motivating incident, twice: `l0_ops_run_and_are_dispatch_cheap`
  failed at the small-matmul assert on battery (ADR 0060 recorded
  610 µs → 3102 µs at 62% load-average 124; this session it went red on a
  mid-session unplug at load average 8.6) and passed on the rerun — same
  code both times.
- The throttle magnitude this ADR normalizes: ADR 0051 L3's 4–10×
  (decode 45→3.5 tok/s; qwen17 prefill walls growing within-process) and
  the R1 cold-start leg (first traced call 6,608 ms on battery vs 75.8 ms
  replay — the pessimistic bound the flip verdict leaned on).
- Implementation gates: `power` unit tests pin the parser against
  recorded `pmset` outputs (AC, battery charging, battery discharging,
  throttled `CPU_Speed_Limit`, garbage → `unknown`); `l0` on battery now
  prints the facts line and passes (assert held on the AC rerun); the
  Dart parser suite covers the same fixtures plus non-mac degrade.
