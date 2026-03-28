import '../client/steam_init.dart';

/// Native init outcome.
final class SteamNativeInitResult {
  const SteamNativeInitResult({
    required this.initCode,
    required this.errorMessage,
  });

  final int initCode;
  final String errorMessage;
}

/// Single callback envelope drained from manual dispatch queue.
final class SteamManualCallback {
  const SteamManualCallback({
    required this.callbackId,
    required this.payloadSize,
    this.apiCallHandle,
    this.apiCallExpectedCallbackId,
    this.apiCallPayloadSize,
  });

  final int callbackId;
  final int payloadSize;

  /// Present only for callback id `703` (`SteamAPICallCompleted_t`).
  final int? apiCallHandle;
  final int? apiCallExpectedCallbackId;
  final int? apiCallPayloadSize;
}

/// Concrete async call result payload loaded from native runtime.
final class SteamApiCallResultPayload {
  const SteamApiCallResultPayload({
    required this.callbackId,
    required this.failed,
    required this.payload,
  });

  final int callbackId;
  final bool failed;
  final List<int> payload;
}

/// Native API shape required by the manual wrapper runtime.
abstract interface class SteamNativeApi {
  bool restartAppIfNecessary(final int appId);

  SteamNativeInitResult initialize();

  void shutdown();

  void runCallbacks();

  bool get supportsManualDispatch;

  void initManualDispatch();

  int get hSteamPipe;

  List<SteamManualCallback> drainManualCallbacks();

  SteamApiCallResultPayload? getApiCallResult({
    required final int apiCallHandle,
    required final int expectedCallbackId,
    required final int callbackBufferSize,
  });

  bool userLoggedOn();

  int userSteamId();

  String personaName();

  int friendCount(final int flags);

  int friendByIndex(final int index, final int flags);

  String friendPersonaName(final int steamId);

  bool requestCurrentStats();

  int? getStatInt32(final String name);

  double? getStatFloat(final String name);

  bool setStatInt32(final String name, final int value);

  bool setStatFloat(final String name, final double value);

  bool storeStats();

  bool? getAchievement(final String name);

  bool setAchievement(final String name);

  bool clearAchievement(final String name);
}

/// Factory creating native runtime adapters for a given init config.
abstract interface class SteamNativeApiFactory {
  SteamNativeApi create(final SteamInitConfig config);
}
