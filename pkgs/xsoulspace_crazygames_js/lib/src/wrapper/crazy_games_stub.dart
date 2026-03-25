export 'enums.dart';
export 'models.dart';

import 'enums.dart';
import 'models.dart';

Never _unsupported() {
  throw UnsupportedError(
    'CrazyGames SDK is available only on web (dart.library.js_interop).',
  );
}

/// Non-web fallback for CrazyGames wrapper.
abstract final class CrazyGames {
  static Future<CrazyGamesClient> init({
    final String expectedGlobal = 'CrazyGames',
  }) async => _unsupported();

  static bool isAvailable({final String expectedGlobal = 'CrazyGames'}) =>
      false;
}

class CrazyGamesClient {
  AdClient get ad => _unsupported();
  BannerClient get banner => _unsupported();
  GameClient get game => _unsupported();
  UserClient get user => _unsupported();
  DataClient get data => _unsupported();
  AnalyticsClient get analytics => _unsupported();
  Environment get environment => _unsupported();
  bool get isQaTool => _unsupported();
}

class AdClient {
  void prefetchAd(final AdType type) => _unsupported();

  Future<void> requestAd(
    final AdType type, {
    final void Function()? adStarted,
    final void Function(SdkError error)? adError,
    final void Function()? adFinished,
  }) async => _unsupported();

  Future<bool> hasAdblock() async => _unsupported();

  Object addAdblockPopupListener(
    final void Function(AdblockPopupState state) listener,
  ) => _unsupported();

  void removeAdblockPopupListener(final Object listener) => _unsupported();

  bool get isAdPlaying => _unsupported();
}

class BannerClient {
  Future<PrefetchedBanner> prefetchBanner(final BannerRequest request) async =>
      _unsupported();

  Future<void> requestBanner(final BannerRequest request) async =>
      _unsupported();

  Future<PrefetchedBanner> prefetchResponsiveBanner(
    final BannerRequest request,
  ) async => _unsupported();

  Future<void> requestResponsiveBanner(final String id) async => _unsupported();

  Future<void> renderPrefetchedBanner(final PrefetchedBanner banner) async =>
      _unsupported();

  void clearBanner(final String id) => _unsupported();

  void clearAllBanners() => _unsupported();

  void requestOverlayBanners(
    final List<OverlayBannerRequest> banners, {
    final void Function(String id, String event, String? value)? callback,
  }) => _unsupported();

  int get activeBannersCount => _unsupported();
}

class GameClient {
  String get link => _unsupported();
  String get id => _unsupported();
  GameSettings get settings => _unsupported();
  bool get isInstantJoin => _unsupported();
  bool get isInstantMultiplayer => _unsupported();
  Map<String, String>? get inviteParams => _unsupported();

  void gameplayStart() => _unsupported();
  void gameplayStop() => _unsupported();
  void loadingStart() => _unsupported();
  void loadingStop() => _unsupported();
  void happytime() => _unsupported();
  String inviteLink(final Map<String, String> params) => _unsupported();
  String showInviteButton(final Map<String, String> params) => _unsupported();
  void hideInviteButton() => _unsupported();
  String? getInviteParam(final String key) => _unsupported();

  Object addSettingsChangeListener(
    final void Function(GameSettings settings) listener,
  ) => _unsupported();

  void removeSettingsChangeListener(final Object listener) => _unsupported();

  Object addJoinRoomListener(
    final void Function(Map<String, String> inviteParams) listener,
  ) => _unsupported();

  void removeJoinRoomListener(final Object listener) => _unsupported();
}

class UserClient {
  bool get isUserAccountAvailable => _unsupported();
  SystemInfo get systemInfo => _unsupported();
  Future<User?> getUser() async => _unsupported();

  Future<FriendsPage> listFriends({
    final int page = 1,
    final int size = 10,
  }) async => _unsupported();

  Future<String> getUserToken() async => _unsupported();
  Future<String> getXsollaUserToken() async => _unsupported();
  Future<User?> showAuthPrompt() async => _unsupported();
  Future<AccountLinkResponse> showAccountLinkPrompt() async => _unsupported();

  Object addAuthListener(final void Function(User? user) listener) =>
      _unsupported();

  void removeAuthListener(final Object listener) => _unsupported();

  void addScore(final int score) => _unsupported();

  void addScoreEncrypted(final int score, final String encryptedScore) =>
      _unsupported();

  void submitScore(final String encryptedScore) => _unsupported();
}

class DataClient {
  void clear() => _unsupported();
  String? getItem(final String key) => _unsupported();
  void removeItem(final String key) => _unsupported();
  void setItem(final String key, final Object? value) => _unsupported();
  void syncUnityGameData() => _unsupported();
}

class AnalyticsClient {
  void trackOrder(
    final PaymentProvider provider,
    final Map<String, Object?> order,
  ) => _unsupported();
}
