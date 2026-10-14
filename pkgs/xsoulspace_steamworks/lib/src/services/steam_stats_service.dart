import '../native/steam_native_api.dart';

/// User stats API.
final class SteamStatsService {
  const SteamStatsService(this._nativeApi);

  final SteamNativeApi _nativeApi;

  Future<bool> requestCurrentStats() async => _nativeApi.requestCurrentStats();

  int? getIntStat(String name) => _nativeApi.getStatInt32(name);

  double? getFloatStat(String name) => _nativeApi.getStatFloat(name);

  bool setIntStat(String name, int value) =>
      _nativeApi.setStatInt32(name, value);

  bool setFloatStat(String name, double value) =>
      _nativeApi.setStatFloat(name, value);

  Future<bool> storeStats() async => _nativeApi.storeStats();
}
