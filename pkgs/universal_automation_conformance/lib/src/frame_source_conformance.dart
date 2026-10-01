import 'dart:async';

import 'package:test/test.dart';
import 'package:universal_screencast/universal_screencast.dart';

/// Contract suite for [FrameSource] implementations.
///
/// Encodes the frame-source invariants: sequences are monotonic,
/// capturedAt never goes backwards, and after [FrameSource.stop] no frame
/// is ever emitted again.
void frameSourceConformanceTests(
  String scenario, {
  required Future<FrameSource> Function() createSource,
  int minimumFrames = 3,
  Duration perFrameTimeout = const Duration(seconds: 10),
}) {
  group('$scenario frame source conformance', () {
    test('emits monotonic, well-formed frames', () async {
      final source = await createSource();
      addTearDown(source.stop);
      final frames = await source
          .start()
          .take(minimumFrames)
          .toList()
          .timeout(perFrameTimeout * minimumFrames);
      var previousSequence = -1;
      var previousCapturedAt = DateTime.fromMicrosecondsSinceEpoch(0);
      for (final frame in frames) {
        expect(frame.sequence, greaterThan(previousSequence));
        expect(frame.revision, greaterThanOrEqualTo(0));
        expect(frame.bytes, isNotEmpty);
        expect(frame.contentType, isNotEmpty);
        expect(
          frame.capturedAt.isBefore(previousCapturedAt),
          isFalse,
          reason: 'capturedAt must never go backwards',
        );
        previousSequence = frame.sequence;
        previousCapturedAt = frame.capturedAt;
      }
    });

    test('emits nothing after stop', () async {
      final source = await createSource();
      final frames = source.start();
      await frames.first.timeout(perFrameTimeout);
      await source.stop();
      final lateArrival = Completer<void>();
      final subscription = frames.listen((_) => lateArrival.complete());
      addTearDown(subscription.cancel);
      expect(
        lateArrival.future.timeout(const Duration(milliseconds: 400)),
        throwsA(isA<TimeoutException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));
    });

    test('stop is idempotent', () async {
      final source = await createSource();
      await source.stop();
      await source.stop();
    });
  });
}
