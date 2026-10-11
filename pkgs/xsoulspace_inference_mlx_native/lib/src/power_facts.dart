/// Power facts (ADR 0061) — a runtime capability fact in the same shape as
/// `chip`: sensed, recorded, gated on, routed by. NEVER commanded: Apple
/// Silicon exposes no user-space control over GPU clocks, power limits, or
/// the sustained-load throttle, and nothing here pretends to.
///
/// The shape is one-to-one with the Rust gates' `power::PowerFacts`
/// (`native/mlx_native/src/power.rs`) — one fact, two consumers. Read
/// fresh on every call: an unplug mid-run is exactly the event the
/// record-the-power-state law exists for, so caching would hide it.
///
/// Sensor failure or non-macOS platforms degrade to
/// [PowerSource.unknown] — never an exception.
library;

import 'dart:io';

enum PowerSource { ac, battery, unknown }

/// `{source, batteryPercent, cpuSpeedLimitPercent}`.
///
/// `cpuSpeedLimitPercent < 100` is the OS's own throttle confession
/// (`pmset -g therm`'s `CPU_Speed_Limit`): the machine is being slowed
/// right now, whatever the power source.
class PowerFacts {
  final PowerSource source;

  /// Battery charge in percent; null on AC or when unknown.
  final int? batteryPercent;

  /// 100 = unlimited; lower = the OS is throttling NOW. Null when unknown.
  final int? cpuSpeedLimitPercent;

  const PowerFacts({
    required this.source,
    this.batteryPercent,
    this.cpuSpeedLimitPercent,
  });

  /// Reads the facts fresh. Non-macOS (and any `pmset` failure) yields
  /// `PowerSource.unknown`.
  static Future<PowerFacts> current() async {
    if (!Platform.isMacOS) return const PowerFacts(source: PowerSource.unknown);
    String? ps;
    String? therm;
    try {
      final r = await Process.run('pmset', <String>['-g', 'ps']);
      if (r.exitCode == 0) ps = r.stdout as String;
      final t = await Process.run('pmset', <String>['-g', 'therm']);
      if (t.exitCode == 0) therm = t.stdout as String;
    } on ProcessException {
      return const PowerFacts(source: PowerSource.unknown);
    }
    return PowerFacts.parse(ps: ps, therm: therm);
  }

  /// Pure parser — pin-tested against recorded `pmset` outputs.
  factory PowerFacts.parse({String? ps, String? therm}) {
    var source = PowerSource.unknown;
    int? percent;
    for (final line in (ps ?? '').split('\n')) {
      final s = _parseSource(line);
      if (s != PowerSource.unknown) source = s;
      final p = _parsePercent(line);
      if (p != null) percent = p;
    }
    if (source == PowerSource.ac) percent = null;
    int? limit;
    for (final line in (therm ?? '').split('\n')) {
      final l = _parseSpeedLimit(line);
      if (l != null) limit = l;
    }
    return PowerFacts(
      source: source,
      batteryPercent: percent,
      cpuSpeedLimitPercent: limit,
    );
  }

  static PowerSource _parseSource(String line) {
    if (line.contains("'AC Power'")) return PowerSource.ac;
    if (line.contains("'Battery Power'")) return PowerSource.battery;
    return PowerSource.unknown;
  }

  /// The number directly before the first `%` (the battery row).
  static int? _parsePercent(String line) {
    final before = line.split('%').first;
    final tokens = before.split(RegExp(r'\s')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;
    return int.tryParse(tokens.last);
  }

  /// `CPU_Speed_Limit = 100` from `pmset -g therm`.
  static int? _parseSpeedLimit(String line) {
    if (!line.trimLeft().startsWith('CPU_Speed_Limit')) return null;
    final value = line.split('=').last.trim();
    return int.tryParse(value);
  }

  /// One-line provenance for a bench/gate output ("ac", "battery 50%
  /// cpu_limit 58%", "unknown").
  String describe() {
    final b = StringBuffer(switch (source) {
      PowerSource.ac => 'ac',
      PowerSource.battery => 'battery',
      PowerSource.unknown => 'unknown',
    });
    final p = batteryPercent;
    if (p != null) b.write(' $p%');
    final l = cpuSpeedLimitPercent;
    if (l != null && l < 100) b.write(' cpu_limit $l%');
    return b.toString();
  }

  @override
  String toString() => 'PowerFacts(${describe()})';
}
