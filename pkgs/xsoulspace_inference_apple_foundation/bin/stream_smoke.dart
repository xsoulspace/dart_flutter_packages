// Streaming smoke test — real hardware, macOS 26+ with Apple Intelligence.
//
// ```sh
// dart run bin/stream_smoke.dart
// ```
//
// Prints time-to-first-token (TTFT), the streamed text, and the final result.

import 'dart:async';
import 'dart:io';

import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Future<void> main() async {
  final client = AppleFoundationNativeClient();
  await client.load();
  if (!await client.refreshAvailability()) {
    stderr.writeln('engine unavailable');
    exit(1);
  }
  final session = await client.streamStructuredText(
    InferenceRequest(prompt: 'Count from 1 to 5, one number per line.'),
  );
  final sw = Stopwatch()..start();
  var firstDeltaMs = -1;
  var deltas = 0;
  await for (final event in session.events) {
    if (event.type == .partialOutput) {
      deltas++;
      if (firstDeltaMs < 0) {
        firstDeltaMs = sw.elapsedMilliseconds;
        stdout.writeln('TTFT: ${firstDeltaMs}ms');
      }
      stdout.write(event.textDelta);
    }
  }
  final result = await session.result;
  stdout.writeln('\n---');
  stdout.writeln(
    'deltas: $deltas, ok: ${result.success}, '
    'total: ${sw.elapsedMilliseconds}ms',
  );
  exit(result.success ? 0 : 1);
}
