import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_screencast/universal_screencast.dart';

Frame _frame(int sequence) => Frame(
  sourceId: 'conformance',
  sequence: sequence,
  revision: 0,
  bytes: Uint8List.fromList([0xFF, 0xD8, sequence, 0xD9]),
  contentType: 'image/jpeg',
  capturedAt: DateTime.now().toUtc(),
);

/// Contract suite for [FrameSink] implementations.
///
/// Encodes the plagiarism-project invariants: close terminates delivery
/// deterministically, use-after-close is a loud programming error, and a
/// close with error surfaces the error instead of swallowing it.
void frameSinkConformanceTests(
  String scenario, {
  required Future<FrameSink> Function() createSink,
}) {
  group('$scenario frame sink conformance', () {
    test('accepts frames then closes cleanly', () async {
      final sink = await createSink();
      await sink.push(_frame(1));
      await sink.push(_frame(2));
      await sink.close();
    });

    test('push after close throws', () async {
      final sink = await createSink();
      await sink.close();
      await expectLater(sink.push(_frame(3)), throwsA(isA<Object>()));
    });

    test('close is idempotent and reports errors', () async {
      final sink = await createSink();
      await sink.push(_frame(1));
      await sink.close(error: StateError('boom'));
      await sink.close();
    });
  });
}
