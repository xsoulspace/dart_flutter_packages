import '../native/steam_native_api.dart';

/// Achievement operations.
final class SteamAchievementsService {
  const SteamAchievementsService(this._nativeApi);

  final SteamNativeApi _nativeApi;

  bool? getAchievement(String apiName) =>
      _nativeApi.getAchievement(apiName);

  bool setAchievement(String apiName) =>
      _nativeApi.setAchievement(apiName);

  bool clearAchievement(String apiName) =>
      _nativeApi.clearAchievement(apiName);
}
