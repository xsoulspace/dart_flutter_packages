import '../native/steam_native_api.dart';

/// Achievement operations.
final class SteamAchievementsService {
  const SteamAchievementsService(this._nativeApi);

  final SteamNativeApi _nativeApi;

  bool? getAchievement(final String apiName) {
    return _nativeApi.getAchievement(apiName);
  }

  bool setAchievement(final String apiName) {
    return _nativeApi.setAchievement(apiName);
  }

  bool clearAchievement(final String apiName) {
    return _nativeApi.clearAchievement(apiName);
  }
}
