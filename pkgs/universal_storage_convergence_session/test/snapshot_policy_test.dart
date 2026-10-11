import 'package:test/test.dart';
import 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart';

/// shouldCompact contract tests: the pure compaction policy shared by mesh
/// sync and ecsly world sync (provenance: ecsly's ecsly_world_sync_bridge
/// SnapshotPolicy). Defaults 512 ops / 5 minutes; an empty log never
/// compacts; a disabled trigger (null) never fires.
void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  DateTime ago(final Duration d) => now.subtract(d);

  group('size trigger', () {
    test('fires past the default 512 ops', () {
      expect(shouldCompact(logLength: 513, now: now), isTrue);
    });

    test('does not fire at exactly the default 512 ops', () {
      expect(shouldCompact(logLength: 512, now: now), isFalse);
    });

    test('honors parent-chosen thresholds', () {
      expect(shouldCompact(logLength: 11, now: now, maxLogOps: 10), isTrue);
      expect(shouldCompact(logLength: 10, now: now, maxLogOps: 10), isFalse);
    });
  });

  group('interval trigger', () {
    test('fires once the interval elapsed since the last compaction', () {
      expect(
        shouldCompact(
          logLength: 5,
          now: now,
          lastCompactionAt: ago(defaultMinInterval),
        ),
        isTrue,
      );
    });

    test('does not fire before the interval elapses', () {
      expect(
        shouldCompact(
          logLength: 5,
          now: now,
          lastCompactionAt: ago(
            defaultMinInterval - const Duration(milliseconds: 1),
          ),
        ),
        isFalse,
      );
    });

    test('never-compacted owners only fire on size', () {
      expect(shouldCompact(logLength: 5, now: now), isFalse);
    });
  });

  group('empty log', () {
    test('never compacts, no matter how old the last compaction is', () {
      expect(
        shouldCompact(
          logLength: 0,
          now: now,
          lastCompactionAt: ago(const Duration(days: 365)),
        ),
        isFalse,
      );
      expect(shouldCompact(logLength: 0, now: now), isFalse);
    });
  });

  group('disabled triggers (null)', () {
    test('null maxLogOps disables the size trigger', () {
      expect(
        shouldCompact(logLength: 100_000, now: now, maxLogOps: null),
        isFalse,
      );
    });

    test('null minInterval disables the age trigger', () {
      expect(
        shouldCompact(
          logLength: 5,
          now: now,
          lastCompactionAt: ago(const Duration(days: 365)),
          minInterval: null,
        ),
        isFalse,
      );
    });
  });
}
