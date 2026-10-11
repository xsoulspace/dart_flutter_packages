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
4. **Route / pace / probe-energy: the three consumers (implemented
   2026-10-11).**
   - **Routing** (afm `decision_routing.dart`): the router takes a
     host-pushed `powerPressure` (`none` | `throttled`) — the readiness
     pattern, never router-side I/O. `none` (the default) is byte-for-byte
     today's ladder. `throttled` DEMOTES localHost routes below ready
     meshPeer routes: a re-order, never a removal — local stays
     dispatchable (failover returns to it; it serves when it is the only
     option), hosted stays last. `decisionPowerPressureOf(PowerFacts)`
     maps the facts (battery, or `cpuSpeedLimitPercent < 100` →
     throttled); `startPowerPressurePolling` is the one-call host wiring.
     Recorded reality: no production route set mixes local+peer on one
     router today (desktop = single local binding, phone = single peer
     route), so the poller is dead code until a mixed topology lands —
     the seam exists so that landing is one call.
   - **Pacing** (mlx_native `PrefillPacing`): under a real power ceiling
     (battery, or the OS throttling now) the prefill loop rests 8 ms
     between chunks — R5's frame gate proved paced chunks co-schedule
     with the compositor essentially free. Zero effect on AC/unknown
     (err toward speed), prefill-only (never per decode token), one facts
     read per generate call (never per chunk), `LAYA_POWER_PACING=0`
     disables, `LAYA_POWER_PACING_MS=N` retunes. Wired into both the
     qwen and lfm2 `generate_greedy` chunk loops; invisible to Dart.
   - **Energy probe** (`src/bin/energy_probe.rs`): samples IOReport's
     "Energy Model" channels around N laya decisions. IOReport is a
     PRIVATE framework — the probe dlopens it and, when absent, prints
     `energy: NON-CLAIM on this host` and exits 0. **Recorded capability
     gap (darwin 27, M1): the framework is not on disk and the symbols
     are not in the process's default scope — an unentitled user process
     cannot read energy here.** The reroute is an entitlement or a
     root `powermetrics` lane; both are out of scope. The probe is the
     standing lane for any host where IOReport IS reachable.

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
- No energy measurements exist yet — on this host the IOReport gap makes
  joules a non-claim (see consumer 3); the probe lane stands for hosts
  where the framework is reachable.
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
- Consumers (2026-10-11): routing — afm `decision_routing_test.dart`
  18/18 (pressure mapping on all fact states, peer-first under throttle,
  local-served-when-only, throttle-failover to local, the default ladder
  unchanged, poll lifecycle); the 6 other afm reds are stash-proven
  pre-existing (same tests fail on the clean-HEAD state of the two
  touched files, 129+6 there vs 135+6 with the change). Pacing — the
  `prefill_pacing_law` unit test pins every state and both env laws, and
  both fixture batteries (lfm2 4/4, qwen3 3/3) stay green with pacing
  wired into the loops (a sleep touches no math). Energy — the probe
  compiles and its degrade is proven live on darwin 27
  (`energy: NON-CLAIM on this host`); the sampling path stands for hosts
  where the private framework is reachable.
