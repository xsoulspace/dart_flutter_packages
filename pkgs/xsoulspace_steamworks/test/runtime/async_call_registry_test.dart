import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_steamworks/src/runtime/async_call_registry.dart';

void main() {
  test('completes registered call on matching callback id', () async {
    final registry = SteamAsyncCallRegistry();
    addTearDown(registry.dispose);

    final future = registry.register(
      apiCallHandle: 7,
      expectedCallbackId: 1101,
      timeout: const Duration(seconds: 1),
    );

    final completed = registry.complete(
      apiCallHandle: 7,
      callbackId: 1101,
      payload: const <int>[10, 20],
      failed: false,
    );

    expect(completed, true);
    final result = await future;
    expect(result.apiCallHandle, 7);
    expect(result.callbackId, 1101);
    expect(result.payload, const <int>[10, 20]);
    expect(result.failed, false);
  });

  test('ignores completion with mismatched callback id', () async {
    final registry = SteamAsyncCallRegistry();
    addTearDown(registry.dispose);

    final future = registry.register(
      apiCallHandle: 9,
      expectedCallbackId: 1102,
      timeout: const Duration(milliseconds: 100),
    );

    final completed = registry.complete(
      apiCallHandle: 9,
      callbackId: 9999,
      payload: const <int>[0],
      failed: false,
    );

    expect(completed, false);
    await expectLater(future, throwsA(isA<TimeoutException>()));
  });

  test('times out pending calls', () async {
    final registry = SteamAsyncCallRegistry();
    addTearDown(registry.dispose);

    final future = registry.register(
      apiCallHandle: 12,
      expectedCallbackId: 777,
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(future, throwsA(isA<TimeoutException>()));
  });
}
