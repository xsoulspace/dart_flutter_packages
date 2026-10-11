//! Power facts (ADR 0061) — a runtime capability fact in the same shape as
//! `chip`: sensed, recorded, gated on, routed by. NEVER commanded: Apple
//! Silicon exposes no user-space control over GPU clocks, power limits, or
//! the sustained-load throttle, and nothing here pretends to.
//!
//! Facts are read FRESH on every call — an unplug mid-run is exactly the
//! event the gates must see, so caching would hide it. Sensor failure
//! degrades to [`PowerSource::Unknown`], never fails the caller.
//!
//! Gate law (the reason this module exists): perf gates assert ONLY on AC;
//! on battery they run, print the facts beside the measurement, and pass —
//! a battery red for the same code twice paid for that rule (ADR 0060's
//! note, then 2026-10-11). Bit/parity gates are NEVER power-conditioned.

/// Where the power comes from right now.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PowerSource {
    Ac,
    Battery,
    /// `pmset` absent, unreadable, or unrecognized output. Perf gates KEEP
    /// asserting on unknown (no silent weakening); a Metal-capable machine
    /// without `pmset` is not a machine we run on.
    Unknown,
}

impl PowerSource {
    /// Parses the `Now drawing from '…'` line of `pmset -g ps`.
    pub fn parse_ps_line(line: &str) -> PowerSource {
        if line.contains("'AC Power'") {
            PowerSource::Ac
        } else if line.contains("'Battery Power'") {
            PowerSource::Battery
        } else {
            PowerSource::Unknown
        }
    }
}

/// `{source, batteryPercent, cpuSpeedLimitPercent}` — one fact, two
/// consumers (the Rust gates and the Dart `PowerFacts`), one shape.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PowerFacts {
    pub source: PowerSource,
    pub battery_percent: Option<u8>,
    /// The OS's own throttle confession (`pmset -g therm`'s
    /// `CPU_Speed_Limit`): 100 = unlimited, lower = throttled NOW.
    pub cpu_speed_limit: Option<u8>,
}

impl PowerFacts {
    /// One-line provenance for a gate/bench output ("ac", "battery 50%
    /// cpu_limit 58%", "unknown").
    pub fn describe(&self) -> String {
        let mut s = match self.source {
            PowerSource::Ac => "ac".to_string(),
            PowerSource::Battery => "battery".to_string(),
            PowerSource::Unknown => "unknown".to_string(),
        };
        if let Some(p) = self.battery_percent {
            s.push_str(&format!(" {p}%"));
        }
        if let Some(l) = self.cpu_speed_limit {
            if l < 100 {
                s.push_str(&format!(" cpu_limit {l}%"));
            }
        }
        s
    }
}

/// Parses the leading integer of a `pmset -g ps` battery row
/// (` -InternalBattery-0 (id=…)	90%; charging; …`) — the number directly
/// before the first `%`. `None` when the row has none.
pub fn parse_battery_percent(line: &str) -> Option<u8> {
    let before = line.split('%').next()?;
    before.split_whitespace().last()?.parse::<u8>().ok()
}

/// Parses `pmset -g therm`'s `CPU_Speed_Limit = 100` — `None` when absent.
pub fn parse_cpu_speed_limit(output: &str) -> Option<u8> {
    for line in output.lines() {
        if let Some(v) = line.split('=').nth(1) {
            if line.trim_start().starts_with("CPU_Speed_Limit") {
                return v.trim().parse::<u8>().ok();
            }
        }
    }
    None
}

fn read_command(args: &[&str]) -> Option<String> {
    let out = std::process::Command::new(args[0])
        .args(&args[1..])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Reads the facts fresh (an exec or two per call; gates call this once).
/// Non-macOS degrades to `Unknown`.
pub fn facts() -> PowerFacts {
    #[cfg(target_os = "macos")]
    {
        let mut f = PowerFacts { source: PowerSource::Unknown, battery_percent: None, cpu_speed_limit: None };
        if let Some(ps) = read_command(&["pmset", "-g", "ps"]) {
            for line in ps.lines() {
                let src = PowerSource::parse_ps_line(line);
                if src != PowerSource::Unknown {
                    f.source = src;
                }
                if let Some(p) = parse_battery_percent(line) {
                    f.battery_percent = Some(p);
                }
            }
            if f.source == PowerSource::Ac {
                f.battery_percent = None;
            }
        }
        if let Some(therm) = read_command(&["pmset", "-g", "therm"]) {
            f.cpu_speed_limit = parse_cpu_speed_limit(&therm);
        }
        f
    }
    #[cfg(not(target_os = "macos"))]
    {
        PowerFacts { source: PowerSource::Unknown, battery_percent: None, cpu_speed_limit: None }
    }
}

/// The perf-gate helper (ADR 0061 decision 2): reads the facts fresh and
/// applies [`perf_gate_with_facts`].
pub fn perf_gate(gate: &str, ok: bool, detail: &str) {
    perf_gate_with_facts(facts(), gate, ok, detail);
}

/// The gate law, testable on any power state: the assertion holds ONLY on
/// AC — byte-for-byte today's oracle, teeth intact. On battery the
/// measurement prints with a loud non-baseline banner and passes (the
/// deliberate trade: an AC-only oracle; battery detects nothing). On
/// `unknown` it KEEPS asserting — no silent weakening when the sensor is
/// absent.
pub fn perf_gate_with_facts(f: PowerFacts, gate: &str, ok: bool, detail: &str) {
    match f.source {
        PowerSource::Ac | PowerSource::Unknown => {
            assert!(ok, "{gate}: {detail}");
        }
        PowerSource::Battery => {
            eprintln!(
                "POWER-CONTAMINATED — non-baseline (ADR 0061): {gate} {detail} \
                 [power: {}]; AC oracle NOT applied",
                f.describe()
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PS_AC: &str = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=22413411)\t90%; charging; 3:03 remaining present: true\n";
    const PS_BATTERY: &str = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=22413411)\t50%; discharging; 4:12 remaining present: true\n";
    const THERM_OK: &str = "CPU_Scheduler_Limit = 100\nCPU_Available_CPUs = 8\nCPU_Speed_Limit = 100\n";
    const THERM_THROTTLED: &str = "CPU_Scheduler_Limit = 100\nCPU_Available_CPUs = 8\nCPU_Speed_Limit = 58\n";

    #[test]
    fn parses_ac_battery_and_thermal_facts() {
        assert_eq!(PowerSource::parse_ps_line(PS_AC.lines().next().unwrap()), PowerSource::Ac);
        assert_eq!(
            PowerSource::parse_ps_line(PS_BATTERY.lines().next().unwrap()),
            PowerSource::Battery
        );
        assert_eq!(PowerSource::parse_ps_line("Now drawing from 'UPS Power'"), PowerSource::Unknown);
        assert_eq!(parse_battery_percent(PS_AC.lines().nth(1).unwrap()), Some(90));
        assert_eq!(parse_battery_percent(PS_BATTERY.lines().nth(1).unwrap()), Some(50));
        assert_eq!(parse_battery_percent("Now drawing from 'AC Power'"), None);
        assert_eq!(parse_cpu_speed_limit(THERM_OK), Some(100));
        assert_eq!(parse_cpu_speed_limit(THERM_THROTTLED), Some(58));
        assert_eq!(parse_cpu_speed_limit("no such output"), None);
    }

    #[test]
    fn describe_matches_the_recorded_shapes() {
        let ac = PowerFacts { source: PowerSource::Ac, battery_percent: None, cpu_speed_limit: Some(100) };
        assert_eq!(ac.describe(), "ac");
        let batt = PowerFacts {
            source: PowerSource::Battery,
            battery_percent: Some(50),
            cpu_speed_limit: Some(58),
        };
        assert_eq!(batt.describe(), "battery 50% cpu_limit 58%");
        let unknown = PowerFacts { source: PowerSource::Unknown, battery_percent: None, cpu_speed_limit: None };
        assert_eq!(unknown.describe(), "unknown");
    }

    #[test]
    fn perf_gate_law_holds_on_every_power_state() {
        // Battery: a would-be-failing condition ANNOTATES and passes — the
        // banner path is provable on AC by feeding synthetic facts.
        perf_gate_with_facts(
            PowerFacts {
                source: PowerSource::Battery,
                battery_percent: Some(50),
                cpu_speed_limit: Some(58),
            },
            "test.gate",
            false,
            "deliberately failing condition 999us",
        );
        // AC and unknown keep the oracle's teeth: a failing condition panics.
        for src in [PowerSource::Ac, PowerSource::Unknown] {
            let panicked = std::panic::catch_unwind(|| {
                perf_gate_with_facts(
                    PowerFacts { source: src, battery_percent: None, cpu_speed_limit: None },
                    "test.gate",
                    false,
                    "x",
                )
            })
            .is_err();
            assert!(panicked, "{src:?} must assert");
        }
        // And the live wrapper agrees with whatever the machine is on.
        let live = facts();
        if live.source == PowerSource::Battery {
            perf_gate("test.live", false, "banner path on the live machine");
        }
    }
}
