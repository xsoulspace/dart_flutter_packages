// ADR 0061: the Dart PowerFacts parser pins the same recorded `pmset`
// outputs the Rust `power` module pins — one fact, two consumers, one
// shape. The live-reader path degrades to `unknown` off-macOS; on macOS a
// live read is exercised for provenance (facts are never asserted here —
// this is a sensor, not an oracle).
import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart'
    show PowerFacts, PowerSource;

const _psAc = '''
Now drawing from 'AC Power'
 -InternalBattery-0 (id=22413411)\t90%; charging; 3:03 remaining present: true
''';

const _psBattery = '''
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=22413411)\t50%; discharging; 4:12 remaining present: true
''';

const _thermOk = '''
CPU_Scheduler_Limit = 100
CPU_Available_CPUs = 8
CPU_Speed_Limit = 100
''';

const _thermThrottled = '''
CPU_Scheduler_Limit = 100
CPU_Available_CPUs = 8
CPU_Speed_Limit = 58
''';

void main() {
  test('parses AC: source ac, no battery percent', () {
    final f = PowerFacts.parse(ps: _psAc, therm: _thermOk);
    expect(f.source, PowerSource.ac);
    expect(f.batteryPercent, isNull);
    expect(f.cpuSpeedLimitPercent, 100);
    expect(f.describe(), 'ac');
  });

  test('parses battery: source, percent, and the throttle confession', () {
    final f = PowerFacts.parse(ps: _psBattery, therm: _thermThrottled);
    expect(f.source, PowerSource.battery);
    expect(f.batteryPercent, 50);
    expect(f.cpuSpeedLimitPercent, 58);
    expect(f.describe(), 'battery 50% cpu_limit 58%');
  });

  test('garbage and absence degrade to unknown, never throw', () {
    expect(
      PowerFacts.parse(ps: 'no such output', therm: 'junk').source,
      PowerSource.unknown,
    );
    expect(PowerFacts.parse().source, PowerSource.unknown);
    expect(PowerFacts.parse(ps: "Now drawing from 'UPS Power'").source,
        PowerSource.unknown);
    expect(PowerFacts.parse().describe(), 'unknown');
  });

  test('live read completes on every platform and never throws', () async {
    // Non-macOS degrades to unknown by design; macOS exercises the real
    // pmset readers. Either way: the sensor completes, and no power state
    // is asserted here — this is a fact reader, not an oracle.
    final f = await PowerFacts.current();
    expect(f, isA<PowerFacts>());
  });
}
