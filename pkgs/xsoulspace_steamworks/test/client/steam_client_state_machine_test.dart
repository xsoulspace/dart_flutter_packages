import 'package:test/test.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

import '../support/fakes.dart';

void main() {
  test('init/shutdown state machine', () async {
    final fakeApi = FakeSteamNativeApi();
    final client = SteamClient(
      nativeApiFactory: FakeSteamNativeApiFactory(fakeApi),
    );

    final first = await client.initialize(
      const SteamInitConfig(appId: 480, autoPumpCallbacks: false),
    );
    expect(first.success, true);
    expect(client.isInitialized, true);

    final second = await client.initialize(
      const SteamInitConfig(appId: 480, autoPumpCallbacks: false),
    );
    expect(second.success, false);
    expect(second.errorCode, SteamInitErrorCode.alreadyInitialized);

    await client.shutdown();
    expect(client.isInitialized, false);
    expect(fakeApi.shutdownCalled, true);

    await client.shutdown();
    expect(client.isInitialized, false);
  });

  test('native init failure is mapped to SteamInitErrorCode', () async {
    final fakeApi = FakeSteamNativeApi()..initCode = 2;
    final client = SteamClient(
      nativeApiFactory: FakeSteamNativeApiFactory(fakeApi),
    );

    final result = await client.initialize(
      const SteamInitConfig(appId: 480, autoPumpCallbacks: false),
    );

    expect(result.success, false);
    expect(result.errorCode, SteamInitErrorCode.noSteamClient);
    expect(client.isInitialized, false);
  });
}
