import 'package:test/test.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';

void main() {
  group('PresenceConfig (ADR 0031 §5)', () {
    test('presets respect the ttl invariant: ttl = ttlFactor × pingInterval',
        () {
      for (final config in [
        PresenceConfig.interactive,
        PresenceConfig.background,
      ]) {
        expect(config.ttlFactor, PresenceConfig.defaultTtlFactor);
        for (final active in [true, false]) {
          final interval = config.pingInterval(active: active);
          expect(
            config.ttlFor(interval),
            Duration(milliseconds: interval.inMilliseconds * config.ttlFactor),
            reason: 'ttl must be exactly ttlFactor × pingInterval '
                '($config, active: $active)',
          );
        }
      }
    });

    test('activity adapts the interval strictly within the preset bounds',
        () {
      for (final config in [
        PresenceConfig.interactive,
        PresenceConfig.background,
      ]) {
        expect(config.pingInterval(active: true), config.minPingInterval);
        expect(config.pingInterval(active: false), config.maxPingInterval);
      }
      // Interactive is the tighter preset, per ADR 0031 §5.
      expect(
        PresenceConfig.interactive.maxPingInterval,
        lessThan(PresenceConfig.background.minPingInterval),
      );
      expect(
        PresenceConfig.interactive.ttlFor(
          PresenceConfig.interactive.pingInterval(active: false),
        ),
        lessThan(
          PresenceConfig.background.ttlFor(
            PresenceConfig.background.pingInterval(active: false),
          ),
        ),
      );
    });

    test('presets keep their documented shapes', () {
      expect(
        PresenceConfig.interactive.minPingInterval,
        const Duration(seconds: 2),
      );
      expect(
        PresenceConfig.interactive.maxPingInterval,
        const Duration(seconds: 10),
      );
      expect(
        PresenceConfig.background.minPingInterval,
        const Duration(seconds: 15),
      );
      expect(
        PresenceConfig.background.maxPingInterval,
        const Duration(seconds: 60),
      );
    });

    test('a peer expires after ~3 missed pings by default', () {
      const config = PresenceConfig.interactive;
      const interval = Duration(seconds: 10);
      final expiry = config.ttlFor(interval);
      expect(
        expiry.inMilliseconds,
        interval.inMilliseconds * 3,
        reason: 'default ttlFactor is 3 (ADR 0031 §5)',
      );
    });

    test('constructor-level bounds and factor are validated', () {
      const bad = PresenceConfig(
        minPingInterval: Duration(seconds: 10),
        maxPingInterval: Duration(seconds: 2),
      );
      // Ordering is validated at use (Duration ordering is not
      // const-evaluable in the const constructor).
      expect(
        () => bad.pingInterval(active: false),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => bad.ttlFor(const Duration(seconds: 1)),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => PresenceConfig(
          minPingInterval: const Duration(seconds: 1),
          maxPingInterval: const Duration(seconds: 2),
          ttlFactor: 1,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'a peer must survive at least 2 missed pings',
      );
    });
  });
}
