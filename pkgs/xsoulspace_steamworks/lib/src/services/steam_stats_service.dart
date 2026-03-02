import '../native/steam_native_api.dart';

/// User stats API.
final class SteamStatsService {
  const SteamStatsService(this._nativeApi);

  final SteamNativeApi _nativeApi;

  Future<bool> requestCurrentStats() async {
    return _nativeApi.requestCurrentStats();
  }

  int? getIntStat(final String name) {
    return _nativeApi.getStatInt32(name);
  }

  double? getFloatStat(final String name) {
    return _nativeApi.getStatFloat(name);
  }

  bool setIntStat(final String name, final int value) {
    return _nativeApi.setStatInt32(name, value);
  }

  bool setFloatStat(final String name, final double value) {
    return _nativeApi.setStatFloat(name, value);
  }

  Future<bool> storeStats() async {
    return _nativeApi.storeStats();
  }
}
