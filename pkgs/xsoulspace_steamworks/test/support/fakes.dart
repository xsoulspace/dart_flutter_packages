import 'package:xsoulspace_steamworks/src/client/steam_init.dart';
import 'package:xsoulspace_steamworks/src/native/steam_native_api.dart';

final class FakeSteamNativeApiFactory implements SteamNativeApiFactory {
  FakeSteamNativeApiFactory(this.api);

  final FakeSteamNativeApi api;

  @override
  SteamNativeApi create(final SteamInitConfig config) => api;
}

final class FakeSteamNativeApi implements SteamNativeApi {
  bool restartRequired = false;
  int initCode = 0;
  String initMessage = '';
  bool manualDispatchSupport = true;

  bool shutdownCalled = false;
  int runCallbacksCount = 0;
  int manualInitCount = 0;
  int _hSteamPipe = 7;

  bool loggedOn = true;
  int steamId = 76561197960287930;
  String localPersonaName = 'Player';
  List<int> friendIds = <int>[111, 222, 333];
  final Map<int, String> friendNames = <int, String>{
    111: 'Alice',
    222: 'Bob',
    333: 'Charlie',
  };

  final Map<String, int> intStats = <String, int>{};
  final Map<String, double> floatStats = <String, double>{};
  final Map<String, bool> achievements = <String, bool>{};

  final List<SteamManualCallback> pendingCallbacks = <SteamManualCallback>[];
  final Map<int, SteamApiCallResultPayload> apiCallResults =
      <int, SteamApiCallResultPayload>{};

  @override
  bool restartAppIfNecessary(final int appId) => restartRequired;

  @override
  SteamNativeInitResult initialize() =>
      SteamNativeInitResult(initCode: initCode, errorMessage: initMessage);

  @override
  void shutdown() {
    shutdownCalled = true;
  }

  @override
  void runCallbacks() {
    runCallbacksCount++;
  }

  @override
  bool get supportsManualDispatch => manualDispatchSupport;

  @override
  void initManualDispatch() {
    manualInitCount++;
  }

  @override
  int get hSteamPipe => _hSteamPipe;

  set hSteamPipe(final int value) => _hSteamPipe = value;

  @override
  List<SteamManualCallback> drainManualCallbacks() {
    final callbacks = List<SteamManualCallback>.of(pendingCallbacks);
    pendingCallbacks.clear();
    return callbacks;
  }

  @override
  SteamApiCallResultPayload? getApiCallResult({
    required final int apiCallHandle,
    required final int expectedCallbackId,
    required final int callbackBufferSize,
  }) => apiCallResults[apiCallHandle];

  @override
  bool userLoggedOn() => loggedOn;

  @override
  int userSteamId() => steamId;

  @override
  String personaName() => localPersonaName;

  @override
  int friendCount(final int flags) => friendIds.length;

  @override
  int friendByIndex(final int index, final int flags) => friendIds[index];

  @override
  String friendPersonaName(final int steamId) =>
      friendNames[steamId] ?? 'Unknown';

  @override
  bool requestCurrentStats() => true;

  @override
  int? getStatInt32(final String name) => intStats[name];

  @override
  double? getStatFloat(final String name) => floatStats[name];

  @override
  bool setStatInt32(final String name, final int value) {
    intStats[name] = value;
    return true;
  }

  @override
  bool setStatFloat(final String name, final double value) {
    floatStats[name] = value;
    return true;
  }

  @override
  bool storeStats() => true;

  @override
  bool? getAchievement(final String name) => achievements[name];

  @override
  bool setAchievement(final String name) {
    achievements[name] = true;
    return true;
  }

  @override
  bool clearAchievement(final String name) {
    achievements[name] = false;
    return true;
  }
}
