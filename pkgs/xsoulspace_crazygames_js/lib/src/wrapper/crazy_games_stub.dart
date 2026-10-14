import 'enums.dart';
import 'models.dart';

export 'enums.dart';
export 'models.dart';

Never _unsupported() {
  throw UnsupportedError(
    'CrazyGames SDK is available only on web (dart.library.js_interop).',
  );
}

/// Non-web fallback for CrazyGames wrapper.
abstract final class CrazyGames {
  static Future<CrazyGamesClient> init({
    String expectedGlobal = 'CrazyGames',
  }) async => _unsupported();

  static bool isAvailable({String expectedGlobal = 'CrazyGames'}) =>
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
  void prefetchAd(AdType type) => _unsupported();

  Future<void> requestAd(
    AdType type, {
    void Function()? adStarted,
    void Function(SdkError error)? adError,
    void Function()? adFinished,
  }) async => _unsupported();

  Future<bool> hasAdblock() async => _unsupported();

  Object addAdblockPopupListener(
    void Function(AdblockPopupState state) listener,
  ) => _unsupported();

  void removeAdblockPopupListener(Object listener) => _unsupported();

  bool get isAdPlaying => _unsupported();
}

class BannerClient {
  Future<PrefetchedBanner> prefetchBanner(BannerRequest request) async =>
      _unsupported();

  Future<void> requestBanner(BannerRequest request) async =>
      _unsupported();

  Future<PrefetchedBanner> prefetchResponsiveBanner(
    BannerRequest request,
  ) async => _unsupported();

  Future<void> requestResponsiveBanner(String id) async => _unsupported();

  Future<void> renderPrefetchedBanner(PrefetchedBanner banner) async =>
      _unsupported();

  void clearBanner(String id) => _unsupported();

  void clearAllBanners() => _unsupported();

  void requestOverlayBanners(
    List<OverlayBannerRequest> banners, {
    void Function(String id, String event, String? value)? callback,
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
  String inviteLink(Map<String, String> params) => _unsupported();
  String showInviteButton(Map<String, String> params) => _unsupported();
  void hideInviteButton() => _unsupported();
  String? getInviteParam(String key) => _unsupported();

  Object addSettingsChangeListener(
    void Function(GameSettings settings) listener,
  ) => _unsupported();

  void removeSettingsChangeListener(Object listener) => _unsupported();

  Object addJoinRoomListener(
    void Function(Map<String, String> inviteParams) listener,
  ) => _unsupported();

  void removeJoinRoomListener(Object listener) => _unsupported();
}

class UserClient {
  bool get isUserAccountAvailable => _unsupported();
  SystemInfo get systemInfo => _unsupported();
  Future<User?> getUser() async => _unsupported();

  Future<FriendsPage> listFriends({
    int page = 1,
    int size = 10,
  }) async => _unsupported();

  Future<String> getUserToken() async => _unsupported();
  Future<String> getXsollaUserToken() async => _unsupported();
  Future<User?> showAuthPrompt() async => _unsupported();
  Future<AccountLinkResponse> showAccountLinkPrompt() async => _unsupported();

  Object addAuthListener(void Function(User? user) listener) =>
      _unsupported();

  void removeAuthListener(Object listener) => _unsupported();

  void addScore(int score) => _unsupported();

  void addScoreEncrypted(int score, String encryptedScore) =>
      _unsupported();

  void submitScore(String encryptedScore) => _unsupported();
}

class DataClient {
  void clear() => _unsupported();
  String? getItem(String key) => _unsupported();
  void removeItem(String key) => _unsupported();
  void setItem(String key, Object? value) => _unsupported();
  void syncUnityGameData() => _unsupported();
}

class AnalyticsClient {
  void trackOrder(
    PaymentProvider provider,
    Map<String, Object?> order,
  ) => _unsupported();
}
