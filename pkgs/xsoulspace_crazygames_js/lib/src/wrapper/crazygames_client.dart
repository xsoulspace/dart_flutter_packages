import 'converters.dart';
import 'enums.dart';
import 'models.dart';

/// High-level CrazyGames SDK wrapper around JS SDK object.
class CrazyGamesClient {
  CrazyGamesClient(this._sdk);

  final Object _sdk;

  AdClient get ad => AdClient(prop(_sdk, 'ad'));
  BannerClient get banner => BannerClient(prop(_sdk, 'banner'));
  GameClient get game => GameClient(prop(_sdk, 'game'));
  UserClient get user => UserClient(prop(_sdk, 'user'));
  DataClient get data => DataClient(prop(_sdk, 'data'));
  AnalyticsClient get analytics => AnalyticsClient(prop(_sdk, 'analytics'));

  Environment get environment =>
      Environment.fromValue(prop(_sdk, 'environment') as String?);
  bool get isQaTool => asBool(prop(_sdk, 'isQaTool'));
}

class AdClient {
  const AdClient(this._module);

  final Object? _module;

  void prefetchAd(AdType type) {
    jsCall(_module, 'prefetchAd', <Object?>[type.value]);
  }

  Future<void> requestAd(
    AdType type, {
    void Function()? adStarted,
    void Function(SdkError error)? adError,
    void Function()? adFinished,
  }) async {
    final callbacks = <String, Object?>{
      if (adStarted != null)
        'adStarted': allowInterop(() {
          runGuarded(adStarted);
        }),
      if (adError != null)
        'adError': allowInterop((Object? error) {
          runGuarded(() {
            final map = asMap(error);
            adError.call(
              map.isEmpty
                  ? const SdkError(code: 'other', message: 'Unknown error')
                  : SdkError.fromMap(map),
            );
          });
        }),
      if (adFinished != null)
        'adFinished': allowInterop(() {
          runGuarded(adFinished);
        }),
    };

    await jsCallPromise(_module, 'requestAd', <Object?>[
      type.value,
      jsify(callbacks),
    ]);
  }

  Future<bool> hasAdblock() async {
    final result = await jsCallPromise(_module, 'hasAdblock');
    return asBool(result);
  }

  Object addAdblockPopupListener(
    void Function(AdblockPopupState state) listener,
  ) {
    final jsListener = allowInterop((Object? state) {
      runGuarded(() {
        listener.call(
          AdblockPopupState.fromValue(state is String ? state : null),
        );
      });
    });
    jsCall(_module, 'addAdblockPopupListener', <Object?>[jsListener]);
    return jsListener;
  }

  void removeAdblockPopupListener(Object listener) {
    jsCall(_module, 'removeAdblockPopupListener', <Object?>[listener]);
  }

  bool get isAdPlaying => asBool(prop(_module, 'isAdPlaying'));
}

class BannerClient {
  const BannerClient(this._module);

  final Object? _module;

  Future<PrefetchedBanner> prefetchBanner(BannerRequest request) async {
    final result = await jsCallPromise(_module, 'prefetchBanner', <Object?>[
      jsify(request.toJson()),
    ]);
    return PrefetchedBanner.fromMap(asMap(result));
  }

  Future<void> requestBanner(BannerRequest request) async {
    await jsCallPromise(_module, 'requestBanner', <Object?>[
      jsify(request.toJson()),
    ]);
  }

  Future<PrefetchedBanner> prefetchResponsiveBanner(
    BannerRequest request,
  ) async {
    final result = await jsCallPromise(
      _module,
      'prefetchResponsiveBanner',
      <Object?>[jsify(request.toJson())],
    );
    return PrefetchedBanner.fromMap(asMap(result));
  }

  Future<void> requestResponsiveBanner(String id) async {
    await jsCallPromise(_module, 'requestResponsiveBanner', <Object?>[id]);
  }

  Future<void> renderPrefetchedBanner(PrefetchedBanner banner) async {
    await jsCallPromise(_module, 'renderPrefetchedBanner', <Object?>[
      jsify(banner.toJson()),
    ]);
  }

  void clearBanner(String id) {
    jsCall(_module, 'clearBanner', <Object?>[id]);
  }

  void clearAllBanners() {
    jsCall(_module, 'clearAllBanners', const <Object?>[]);
  }

  void requestOverlayBanners(
    List<OverlayBannerRequest> banners, {
    void Function(String id, String event, String? value)? callback,
  }) {
    final payload = banners
        .map((banner) => banner.toJson())
        .toList(growable: false);
    if (callback == null) {
      jsCall(_module, 'requestOverlayBanners', <Object?>[jsify(payload)]);
      return;
    }

    final jsCallback = allowInterop((
      Object? id,
      Object? event,
      Object? value,
    ) {
      runGuarded(() {
        callback.call(
          asString(id),
          asString(event),
          value is String ? value : null,
        );
      });
    });
    jsCall(_module, 'requestOverlayBanners', <Object?>[
      jsify(payload),
      jsCallback,
    ]);
  }

  int get activeBannersCount => asInt(prop(_module, 'activeBannersCount'));
}

class GameClient {
  const GameClient(this._module);

  final Object? _module;

  String get link => asString(prop(_module, 'link'));
  String get id => asString(prop(_module, 'id'));
  GameSettings get settings =>
      GameSettings.fromMap(asMap(prop(_module, 'settings')));
  bool get isInstantJoin => asBool(prop(_module, 'isInstantJoin'));
  bool get isInstantMultiplayer =>
      asBool(prop(_module, 'isInstantMultiplayer'));

  Map<String, String>? get inviteParams {
    final value = asMap(prop(_module, 'inviteParams'));
    if (value.isEmpty) {
      return null;
    }
    return value.map((key, item) => MapEntry(key, asString(item)));
  }

  void gameplayStart() => jsCall(_module, 'gameplayStart', const <Object?>[]);
  void gameplayStop() => jsCall(_module, 'gameplayStop', const <Object?>[]);
  void loadingStart() => jsCall(_module, 'loadingStart', const <Object?>[]);
  void loadingStop() => jsCall(_module, 'loadingStop', const <Object?>[]);
  void happytime() => jsCall(_module, 'happytime', const <Object?>[]);

  String inviteLink(Map<String, String> params) {
    final result = jsCall(_module, 'inviteLink', <Object?>[jsify(params)]);
    return asString(result);
  }

  String showInviteButton(Map<String, String> params) {
    final result = jsCall(_module, 'showInviteButton', <Object?>[
      jsify(params),
    ]);
    return asString(result);
  }

  void hideInviteButton() =>
      jsCall(_module, 'hideInviteButton', const <Object?>[]);

  String? getInviteParam(String key) {
    final result = jsCall(_module, 'getInviteParam', <Object?>[key]);
    return result as String?;
  }

  Object addSettingsChangeListener(
    void Function(GameSettings settings) listener,
  ) {
    final jsListener = allowInterop((Object? value) {
      runGuarded(() => listener.call(GameSettings.fromMap(asMap(value))));
    });
    jsCall(_module, 'addSettingsChangeListener', <Object?>[jsListener]);
    return jsListener;
  }

  void removeSettingsChangeListener(Object listener) {
    jsCall(_module, 'removeSettingsChangeListener', <Object?>[listener]);
  }

  Object addJoinRoomListener(
    void Function(Map<String, String> inviteParams) listener,
  ) {
    final jsListener = allowInterop((Object? value) {
      runGuarded(() {
        final map = asMap(
          value,
        ).map((key, item) => MapEntry(key, asString(item)));
        listener.call(map);
      });
    });
    jsCall(_module, 'addJoinRoomListener', <Object?>[jsListener]);
    return jsListener;
  }

  void removeJoinRoomListener(Object listener) {
    jsCall(_module, 'removeJoinRoomListener', <Object?>[listener]);
  }
}

class UserClient {
  const UserClient(this._module);

  final Object? _module;

  bool get isUserAccountAvailable =>
      asBool(prop(_module, 'isUserAccountAvailable'));
  SystemInfo get systemInfo =>
      SystemInfo.fromMap(asMap(prop(_module, 'systemInfo')));

  Future<User?> getUser() async {
    final result = await jsCallPromise(_module, 'getUser');
    if (result == null) {
      return null;
    }
    final map = asMap(result);
    if (map.isEmpty) {
      return null;
    }
    return User.fromMap(map);
  }

  Future<FriendsPage> listFriends({
    int page = 1,
    int size = 10,
  }) async {
    final result = await jsCallPromise(_module, 'listFriends', <Object?>[
      jsify(FriendsPageOptions(page: page, size: size).toJson()),
    ]);
    return FriendsPage.fromMap(asMap(result));
  }

  Future<String> getUserToken() async {
    final result = await jsCallPromise(_module, 'getUserToken');
    return asString(result);
  }

  Future<String> getXsollaUserToken() async {
    final result = await jsCallPromise(_module, 'getXsollaUserToken');
    return asString(result);
  }

  Future<User?> showAuthPrompt() async {
    final result = await jsCallPromise(_module, 'showAuthPrompt');
    if (result == null) {
      return null;
    }
    final map = asMap(result);
    if (map.isEmpty) {
      return null;
    }
    return User.fromMap(map);
  }

  Future<AccountLinkResponse> showAccountLinkPrompt() async {
    final result = await jsCallPromise(_module, 'showAccountLinkPrompt');
    return AccountLinkResponse.fromMap(asMap(result));
  }

  Object addAuthListener(void Function(User? user) listener) {
    final jsListener = allowInterop((Object? value) {
      runGuarded(() {
        final map = asMap(value);
        if (map.isEmpty) {
          listener.call(null);
          return;
        }
        listener.call(User.fromMap(map));
      });
    });
    jsCall(_module, 'addAuthListener', <Object?>[jsListener]);
    return jsListener;
  }

  void removeAuthListener(Object listener) {
    jsCall(_module, 'removeAuthListener', <Object?>[listener]);
  }

  void addScore(int score) {
    jsCall(_module, 'addScore', <Object?>[score]);
  }

  void addScoreEncrypted(int score, String encryptedScore) {
    jsCall(_module, 'addScoreEncrypted', <Object?>[score, encryptedScore]);
  }

  void submitScore(String encryptedScore) {
    jsCall(_module, 'submitScore', <Object?>[
      jsify(<String, Object?>{'encryptedScore': encryptedScore}),
    ]);
  }
}

class DataClient {
  const DataClient(this._module);

  final Object? _module;

  void clear() => jsCall(_module, 'clear', const <Object?>[]);

  String? getItem(String key) {
    final result = jsCall(_module, 'getItem', <Object?>[key]);
    return result as String?;
  }

  void removeItem(String key) {
    jsCall(_module, 'removeItem', <Object?>[key]);
  }

  void setItem(String key, Object? value) {
    jsCall(_module, 'setItem', <Object?>[key, value]);
  }

  void syncUnityGameData() {
    jsCall(_module, 'syncUnityGameData', const <Object?>[]);
  }
}

class AnalyticsClient {
  const AnalyticsClient(this._module);

  final Object? _module;

  void trackOrder(
    PaymentProvider provider,
    Map<String, Object?> order,
  ) {
    jsCall(_module, 'trackOrder', <Object?>[provider.value, jsify(order)]);
  }
}
