import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_steamworks/src/native/steam_native_api.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

import '../support/fakes.dart';

void main() {
  test('auto pump starts and stops with lifecycle', () async {
    final fakeApi = FakeSteamNativeApi();
    final client = SteamClient(
      nativeApiFactory: FakeSteamNativeApiFactory(fakeApi),
    );

    final result = await client.initialize(
      const SteamInitConfig(
        appId: 480,
        callbackInterval: Duration(milliseconds: 10),
      ),
    );
    expect(result.success, true);

    await Future<void>.delayed(const Duration(milliseconds: 45));
    final pumpedWhileRunning = fakeApi.runCallbacksCount;
    expect(pumpedWhileRunning, greaterThanOrEqualTo(2));

    await client.shutdown();

    final countAfterShutdown = fakeApi.runCallbacksCount;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(fakeApi.runCallbacksCount, countAfterShutdown);
  });

  test(
    'manual pump executes one callback frame when auto pump disabled',
    () async {
      final fakeApi = FakeSteamNativeApi();
      final client = SteamClient(
        nativeApiFactory: FakeSteamNativeApiFactory(fakeApi),
      );

      final result = await client.initialize(
        const SteamInitConfig(appId: 480, autoPumpCallbacks: false),
      );
      expect(result.success, true);

      final before = fakeApi.runCallbacksCount;
      client.runCallbacksOnce();
      expect(fakeApi.runCallbacksCount, before + 1);

      await client.shutdown();
    },
  );

  test('async callback completion emits resolved event', () async {
    final fakeApi = FakeSteamNativeApi();
    final client = SteamClient(
      nativeApiFactory: FakeSteamNativeApiFactory(fakeApi),
    );

    final events = <SteamEvent>[];
    final sub = client.events.listen(events.add);
    addTearDown(() async => sub.cancel());

    final result = await client.initialize(
      const SteamInitConfig(appId: 480, autoPumpCallbacks: false),
    );
    expect(result.success, true);

    fakeApi.pendingCallbacks.add(
      const SteamManualCallback(
        callbackId: 703,
        payloadSize: 16,
        apiCallHandle: 42,
        apiCallExpectedCallbackId: 1101,
        apiCallPayloadSize: 32,
      ),
    );
    fakeApi.apiCallResults[42] = const SteamApiCallResultPayload(
      callbackId: 1101,
      failed: false,
      payload: <int>[1, 2, 3],
    );

    client.runCallbacksOnce();
    await Future<void>.delayed(Duration.zero);

    expect(
      events.whereType<SteamCallbackEvent>().any(
        (final e) => e.callbackId == 703,
      ),
      true,
    );

    await client.shutdown();
  });
}
