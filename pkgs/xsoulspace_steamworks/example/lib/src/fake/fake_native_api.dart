import 'package:xsoulspace_steamworks/src/client/steam_init.dart';
import 'package:xsoulspace_steamworks/src/native/steam_native_api.dart';

final class ExampleFakeSteamNativeApiFactory implements SteamNativeApiFactory {
  const ExampleFakeSteamNativeApiFactory();

  @override
  SteamNativeApi create(final SteamInitConfig config) => _FakeSteamNativeApi();
}

final class _FakeSteamNativeApi implements SteamNativeApi {
  final Map<String, int> _intStats = <String, int>{};
  final Map<String, double> _floatStats = <String, double>{};
  final Map<String, bool> _achievements = <String, bool>{};

  @override
  List<SteamManualCallback> drainManualCallbacks() =>
      const <SteamManualCallback>[];

  @override
  int friendByIndex(final int index, final int flags) {
    return const <int>[1001, 1002, 1003][index];
  }

  @override
  int friendCount(final int flags) => 3;

  @override
  String friendPersonaName(final int steamId) {
    switch (steamId) {
      case 1001:
        return 'Alice';
      case 1002:
        return 'Bob';
      case 1003:
        return 'Charlie';
      default:
        return 'Unknown';
    }
  }

  @override
  bool clearAchievement(final String name) {
    _achievements[name] = false;
    return true;
  }

  @override
  SteamApiCallResultPayload? getApiCallResult({
    required final int apiCallHandle,
    required final int expectedCallbackId,
    required final int callbackBufferSize,
  }) {
    return null;
  }

  @override
  bool? getAchievement(final String name) => _achievements[name];

  @override
  double? getStatFloat(final String name) => _floatStats[name];

  @override
  int? getStatInt32(final String name) => _intStats[name];

  @override
  int get hSteamPipe => 1;

  @override
  void initManualDispatch() {}

  @override
  SteamNativeInitResult initialize() {
    return const SteamNativeInitResult(initCode: 0, errorMessage: '');
  }

  @override
  String personaName() => 'FakeUser';

  @override
  bool requestCurrentStats() => true;

  @override
  bool restartAppIfNecessary(final int appId) => false;

  @override
  void runCallbacks() {}

  @override
  bool setAchievement(final String name) {
    _achievements[name] = true;
    return true;
  }

  @override
  bool setStatFloat(final String name, final double value) {
    _floatStats[name] = value;
    return true;
  }

  @override
  bool setStatInt32(final String name, final int value) {
    _intStats[name] = value;
    return true;
  }

  @override
  void shutdown() {}

  @override
  bool storeStats() => true;

  @override
  bool get supportsManualDispatch => false;

  @override
  bool userLoggedOn() => true;

  @override
  int userSteamId() => 123456789;
}
