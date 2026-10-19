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

## The charge-current hole (found 2026-10-18, closed as a recorded gap)

**pmset "AC" ≠ charge current.** `pmset -g ps` reports the *source*
("AC Power") while the adapter may deliver only a trickle. Measured on this
machine's 8 W USB brick: `AC Power` with ioreg `Amperage` = 149 mA
(≈1.6 W at 5% SoC), and ~0 under GPU load — break-even; GPU work stalls
charging. So perf-gate "on AC" requires **real charge current**: the gate
input is `ioreg -rn AppleSmartBattery` → `Amperage` (mA; strongly positive =
actually charging) read under load — not the pmset source flag. Wiring that
check into `PowerFacts` (Dart + Rust, one shape) is the recorded follow-up;
until it lands, treat `ac` on a weak brick as non-baseline and record
Amperage beside every number.

## Non-claims (recorded, do not re-litigate)

- AC is the calibration point, not a guarantee — sustained load can still
  see thermal pressure on AC.
- Battery % and age shift the cap: the same workload throttles
  differently at 20% vs 90%.
- Perf gates on battery detect **nothing** — that's the deliberate trade.
- iOS Low Power Mode: detect-only, no opt-out.
- No energy measurements yet (IOReport = future work).

## Consumers (live, ADR 0061)

1. **Routing** — afm's `RoutedDecisionProvider` takes a host-pushed
   `powerPressure` (`none` = today's ladder; `throttled` demotes the local
   tier below a ready mesh peer — a re-order, never a removal; hosted
   stays last). Map facts with `decisionPowerPressureOf(PowerFacts)`, wire
   with `startPowerPressurePolling(provider)` (one call, stop closure
   returned). No production route set mixes local+peer today, so the
   poller is dormant until a mixed topology lands.
2. **Pacing** — `PrefillPacing` in the Rust generate loops: under battery
   or an OS throttle confession, the prefill loop rests 8 ms between
   chunks (`LAYA_POWER_PACING=0` disables, `LAYA_POWER_PACING_MS=N`
   retunes). Zero effect on AC/unknown; prefill-only; one facts read per
   generate call. Invisible to Dart.
3. **Energy probe** — `cargo run --bin energy_probe` samples IOReport
   Energy Model channels around N laya decisions. **Recorded gap: darwin
   27 does not expose IOReport to unentitled processes** — the probe
   prints `energy: NON-CLAIM on this host` and exits 0; the lane stands
   for hosts where the framework is reachable.
