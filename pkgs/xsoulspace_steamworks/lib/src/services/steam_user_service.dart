import '../native/steam_native_api.dart';

/// User identity and login state helpers.
final class SteamUserService {
  const SteamUserService(this._nativeApi);

  final SteamNativeApi _nativeApi;

  /// Whether current Steam user is logged on.
  bool get isLoggedOn => _nativeApi.userLoggedOn();

  /// Current local SteamID (uint64 as Dart int).
  int get steamId => _nativeApi.userSteamId();
}
