import '../native/steam_native_api.dart';

/// Friends and persona operations.
final class SteamFriendsService {
  const SteamFriendsService(this._nativeApi);

  static const int friendFlagImmediate = 0x04;

  final SteamNativeApi _nativeApi;

  /// Local persona display name.
  String get personaName => _nativeApi.personaName();

  int getFriendCount({final int flags = friendFlagImmediate}) {
    return _nativeApi.friendCount(flags);
  }

  List<int> getFriendSteamIds({final int flags = friendFlagImmediate}) {
    final count = _nativeApi.friendCount(flags);
    if (count <= 0) {
      return const <int>[];
    }

    final friends = <int>[];
    for (var i = 0; i < count; i++) {
      friends.add(_nativeApi.friendByIndex(i, flags));
    }
    return List<int>.unmodifiable(friends);
  }

  String getFriendPersonaName(final int steamId) {
    return _nativeApi.friendPersonaName(steamId);
  }
}
