"""Power snapshot (POWER.md law) for every recorded number in this lane.

The charge-current hole (POWER.md, found 2026-10-18): `pmset` saying
"AC Power" is NOT charge current — the 8 W brick trickle-charges at ~1.6 W
while claiming AC. The gate input is the ioreg AppleSmartBattery Amperage.
This helper returns both, so a run record can carry the honest pair.

Stdlib only (subprocess + json); safe to import anywhere.
"""

import json
import re
import subprocess


def _run(args):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout if out.returncode == 0 else None


def pmset_source():
    """'AC Power' | 'Battery Power' | None — the pmset claim, NOT the truth."""
    out = _run(["pmset", "-g", "ps"])
    if not out:
        return None
    m = re.search(r"Now drawing from '([^']+)'", out)
    return m.group(1) if m else None


def battery_amperage_ma():
    """Signed mA from ioreg AppleSmartBattery (negative = discharging).
    None when the sensor is absent/unreadable — recorded as absent, never
    guessed."""
    out = _run(["ioreg", "-rn", "AppleSmartBattery"])
    if not out:
        return None
    m = re.search(r'"Amperage"\s*=\s*(-?\d+)', out)
    if not m:
        return None
    v = int(m.group(1))
    if v >= 2 ** 63:          # ioreg prints negatives as unsigned 64-bit
        v -= 2 ** 64
    return v


def battery_percent():
    out = _run(["ioreg", "-rn", "AppleSmartBattery"])
    if not out:
        return None
    m = re.search(r'"CurrentCapacity"\s*=\s*(\d+)', out)
    return int(m.group(1)) if m else None


def snapshot():
    """One dict to stamp beside any recorded number."""
    ma = battery_amperage_ma()
    watts = None
    if ma is not None and -2 ** 62 < ma < 2 ** 62:
        watts = round(abs(ma) * 11.4 / 1000.0, 2)
    return {
        "pmset_source": pmset_source(),
        "amperage_ma": ma,
        "estimated_watts": watts,
        "battery_percent": battery_percent(),
        "law": "pmset 'AC' is not charge current; Amperage is the gate input",
    }


if __name__ == "__main__":
    print(json.dumps(snapshot(), indent=2))
