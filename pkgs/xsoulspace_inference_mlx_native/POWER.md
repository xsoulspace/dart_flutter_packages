# POWER.md — the power laws for benches, gates, and agents

One screen. Read this before running any perf benchmark or perf gate on
Apple Silicon. Full decision: [ADR 0061](../../../docs/decisions/0061_power_facts_and_power_aware_gates.md).

## The three laws

1. **You cannot command power.** No API on Apple Silicon raises GPU/CPU
   clocks or power limits. `caffeinate` blocks sleep, NOT throttling.
   Anything claiming otherwise is folklore.
2. **Perf numbers without a power state are non-evidence.** Battery
   throttles sustained GPU *and* CPU work **4–10×** (decode 45→3.5 tok/s).
   Record the state beside every number.
3. **Perf gates assert ONLY on AC.** On battery they run, print
   `POWER-CONTAMINATED — non-baseline (ADR 0061)`, and pass. On AC the
   oracle is unchanged. Bit/parity gates are NEVER power-conditioned —
   they must trip anywhere, anytime.

## Sense it (one call)

```dart
final f = await PowerFacts.current();          // lib/src/power_facts.dart
print(f.describe());                            // "ac" | "battery 50% cpu_limit 58%" | "unknown"
```

```rust
mlx_native::power::facts().describe()           // native/mlx_native/src/power.rs — same shape
```

`cpu_limit < 100` = the OS is throttling RIGHT NOW (its own confession,
from `pmset -g therm`). Facts are read fresh every call — an unplug
mid-run is the event we care about. `unknown` never throws, and perf
gates keep asserting on `unknown` (no silent weakening).

## The gate contract

| Gate kind | On AC | On battery | On unknown |
|---|---|---|---|
| Perf (l0 dispatch, tok/s rows, sweeps) | **asserts** (full oracle) | runs + `POWER-CONTAMINATED` banner + passes | **asserts** |
| Bit/parity (fixtures, plan parity, sweep) | trips | **trips** — no exceptions | trips |

`mlx_native::power::perf_gate(name, ok, detail)` implements the perf row.

## Non-claims (recorded, do not re-litigate)

- AC is the calibration point, not a guarantee — sustained load can still
  see thermal pressure on AC.
- Battery % and age shift the cap: the same workload throttles
  differently at 20% vs 90%.
- Perf gates on battery detect **nothing** — that's the deliberate trade.
- iOS Low Power Mode: detect-only, no opt-out.
- No energy measurements yet (IOReport = future work).

## Named consumers (not yet built)

1. **Routing** — afm's tier ladder treats throttled/battery states as a
   reason to move sustained lanes (2k–8k prefill, long decode) to
   mesh/remote; laya's ~90 ms burst decisions stay local.
2. **Pacing** — inter-chunk pacing on throttled states, on top of R5's
   chunked prefill.
3. **Energy probe** — IOReport Energy Model: joules per decision, the
   dimension that would let rungs be judged on battery.
