import 'converters.dart';
import 'enums.dart';
import 'models.dart';

/// High-level Yandex Games SDK wrapper around JS SDK object.
class YsdkClient {
  YsdkClient.fromSdk(this._sdk, {required this.signed});

  final Object _sdk;
  final bool signed;

  YsdkAdvClient get adv => YsdkAdvClient(prop(_sdk, 'adv'));
  YsdkAuthClient get auth => YsdkAuthClient(prop(_sdk, 'auth'));
  YsdkClipboardClient get clipboard =>
      YsdkClipboardClient(prop(_sdk, 'clipboard'));
  YsdkFeaturesClient get features => YsdkFeaturesClient(prop(_sdk, 'features'));
  YsdkFeedbackClient get feedback => YsdkFeedbackClient(prop(_sdk, 'feedback'));
  YsdkLeaderboardsClient get leaderboards =>
      YsdkLeaderboardsClient(prop(_sdk, 'leaderboards'));
  YsdkMultiplayerClient get multiplayer =>
      YsdkMultiplayerClient(prop(_sdk, 'multiplayer'));
  YsdkPaymentsClient get payments =>
      YsdkPaymentsClient(prop(_sdk, 'payments'), signed: signed);
  YsdkScreenClient get screen => YsdkScreenClient(prop(_sdk, 'screen'));
  YsdkShortcutClient get shortcut => YsdkShortcutClient(prop(_sdk, 'shortcut'));
  YsdkDeviceInfo get deviceInfo => YsdkDeviceInfo(prop(_sdk, 'deviceInfo'));
  YsdkEnvironment get environment => YsdkEnvironment(prop(_sdk, 'environment'));

  Future<void> dispatchEvent(
    final SdkEventName eventName, {
    final Map<String, Object?>? detail,
  }) async {
    await jsCallPromise(_sdk, 'dispatchEvent', <Object?>[
      eventName.value,
      if (detail != null) jsify(detail),
    ]);
  }

  Future<Map<String, String>> getFlags({
    final List<ClientFeatureModel>? clientFeatures,
    final Map<String, String>? defaultFlags,
  }) async {
    final params = <String, Object?>{};
    if (clientFeatures != null) {
      params['clientFeatures'] = clientFeatures
          .map((final item) => item.toJson())
          .toList();
    }
    if (defaultFlags != null) {
      params['defaultFlags'] = defaultFlags;
    }

    final result = await jsCallPromise(
      _sdk,
      'getFlags',
      params.isEmpty ? const <Object?>[] : <Object?>[jsify(params)],
    );

    final map = asMap(result);
    return map.map((final key, final value) => MapEntry(key, asString(value)));
  }

  Future<YsdkLegacyLeaderboardsClient> getLegacyLeaderboards() async {
    final result = await jsCallPromise(_sdk, 'getLeaderboards');
    return YsdkLegacyLeaderboardsClient(result);
  }

  Future<YsdkPaymentsClient> getPaymentsUnsigned() async {
    final result = await jsCallPromise(_sdk, 'getPayments', <Object?>[
      jsify(<String, Object?>{'signed': false}),
    ]);
    return YsdkPaymentsClient(result, signed: false);
  }

  Future<YsdkPaymentsClient> getPaymentsSigned() async {
    final result = await jsCallPromise(_sdk, 'getPayments', <Object?>[
      jsify(<String, Object?>{'signed': true}),
    ]);
    return YsdkPaymentsClient(result, signed: true);
  }

  Future<YsdkPlayer> getPlayerUnsigned() async {
    final result = await jsCallPromise(_sdk, 'getPlayer', <Object?>[
      jsify(<String, Object?>{'signed': false}),
    ]);
    return YsdkPlayer(result);
  }

  Future<SignatureModel> getPlayerSigned() async {
    final result = await jsCallPromise(_sdk, 'getPlayer', <Object?>[
      jsify(<String, Object?>{'signed': true}),
    ]);
    return SignatureModel.fromMap(asMap(result));
  }

  Future<Object?> getStorage() => jsCallPromise(_sdk, 'getStorage');

  Future<bool> isAvailableMethod(final String methodName) async {
    final result = await jsCallPromise(_sdk, 'isAvailableMethod', <Object?>[
      methodName,
    ]);
    return asBool(result);
  }

  double serverTime() {
    final value = jsCall(_sdk, 'serverTime', const <Object?>[]);
    if (value is num) {
      return value.toDouble();
    }
    return asInt(value).toDouble();
  }
}

class YsdkAdvClient {
  const YsdkAdvClient(this._module);

  final Object? _module;

  Future<BannerAdvStatus> getBannerAdvStatus() async {
    final map = asMap(await jsCallPromise(_module, 'getBannerAdvStatus'));
    return BannerAdvStatus(
      stickyAdvIsShowing: asBool(map['stickyAdvIsShowing']),
      reason: map['reason'] == null
          ? null
          : StickyAdvError.fromValue(asString(map['reason'])),
    );
  }

  Future<BannerAdvShowResult> showBannerAdv() async {
    final map = asMap(await jsCallPromise(_module, 'showBannerAdv'));
    return BannerAdvShowResult(
      reason: map['reason'] == null
          ? null
          : StickyAdvError.fromValue(asString(map['reason'])),
    );
  }

  Future<BannerAdvHideResult> hideBannerAdv() async {
    final map = asMap(await jsCallPromise(_module, 'hideBannerAdv'));
    return BannerAdvHideResult(
      stickyAdvIsShowing: asBool(map['stickyAdvIsShowing']),
    );
  }

  void showFullscreenAdv({final FullscreenAdvCallbacks? callbacks}) {
    final jsCallbacks = <String, Object?>{
      if (callbacks?.onOpen != null)
        'onOpen': allowInterop(() => callbacks!.onOpen!.call()),
      if (callbacks?.onClose != null)
        'onClose': allowInterop(
          (final Object? wasShown) =>
              callbacks!.onClose!.call(asBool(wasShown)),
        ),
      if (callbacks?.onOffline != null)
        'onOffline': allowInterop(() => callbacks!.onOffline!.call()),
      if (callbacks?.onError != null)
        'onError': allowInterop(
          (final Object? error) => callbacks!.onError!.call(error),
        ),
    };

    if (jsCallbacks.isEmpty) {
      jsCall(_module, 'showFullscreenAdv', const <Object?>[]);
      return;
    }

    jsCall(_module, 'showFullscreenAdv', <Object?>[
      jsify(<String, Object?>{'callbacks': jsCallbacks}),
    ]);
  }

  void showRewardedVideo({final RewardedVideoCallbacks? callbacks}) {
    final jsCallbacks = <String, Object?>{
      if (callbacks?.onOpen != null)
        'onOpen': allowInterop(() => callbacks!.onOpen!.call()),
      if (callbacks?.onClose != null)
        'onClose': allowInterop(() => callbacks!.onClose!.call()),
      if (callbacks?.onRewarded != null)
        'onRewarded': allowInterop(() => callbacks!.onRewarded!.call()),
      if (callbacks?.onError != null)
        'onError': allowInterop(
          (final Object? error) => callbacks!.onError!.call(error),
        ),
    };

    if (jsCallbacks.isEmpty) {
      jsCall(_module, 'showRewardedVideo', const <Object?>[]);
      return;
    }

    jsCall(_module, 'showRewardedVideo', <Object?>[
      jsify(<String, Object?>{'callbacks': jsCallbacks}),
    ]);
  }
}

class YsdkAuthClient {
  const YsdkAuthClient(this._module);

  final Object? _module;

  Future<void> openAuthDialog() async {
    await jsCallPromise(_module, 'openAuthDialog');
  }
}

class YsdkClipboardClient {
  const YsdkClipboardClient(this._module);

  final Object? _module;

  void writeText(final String text) {
    jsCall(_module, 'writeText', <Object?>[text]);
  }
}

class YsdkFeaturesClient {
  const YsdkFeaturesClient(this._module);

  final Object? _module;

  YsdkGameplayFeature get gameplay =>
      YsdkGameplayFeature(prop(_module, 'GameplayAPI'));

  YsdkGamesFeature get games => YsdkGamesFeature(prop(_module, 'GamesAPI'));

  YsdkLoadingFeature get loading =>
      YsdkLoadingFeature(prop(_module, 'LoadingAPI'));
}

class YsdkGameplayFeature {
  const YsdkGameplayFeature(this._module);

  final Object? _module;

  void start() => jsCall(_module, 'start', const <Object?>[]);
  void stop() => jsCall(_module, 'stop', const <Object?>[]);
}

class YsdkGamesFeature {
  const YsdkGamesFeature(this._module);

  final Object? _module;

  Future<GamesListResult> getAllGames() async {
    final map = asMap(await jsCallPromise(_module, 'getAllGames'));
    final games = asList(
      map['games'],
    ).map(asMap).map(GameModel.fromMap).toList(growable: false);
    return GamesListResult(
      developerUrl: asString(map['developerURL']),
      games: games,
    );
  }

  Future<GameByIdResult> getGameById(final int id) async {
    final map = asMap(
      await jsCallPromise(_module, 'getGameByID', <Object?>[id]),
    );
    final gameMap = asMap(map['game']);
    return GameByIdResult(
      isAvailable: asBool(map['isAvailable']),
      game: gameMap.isEmpty ? null : GameModel.fromMap(gameMap),
    );
  }
}

class YsdkLoadingFeature {
  const YsdkLoadingFeature(this._module);

  final Object? _module;

  void ready() => jsCall(_module, 'ready', const <Object?>[]);
}

class YsdkFeedbackClient {
  const YsdkFeedbackClient(this._module);

  final Object? _module;

  Future<FeedbackAvailability> canReview() async {
    final map = asMap(await jsCallPromise(_module, 'canReview'));
    return FeedbackAvailability(
      value: asBool(map['value']),
      reason: map['reason'] == null
          ? null
          : FeedbackError.fromValue(asString(map['reason'])),
    );
  }

  Future<FeedbackRequestResult> requestReview() async {
    final map = asMap(await jsCallPromise(_module, 'requestReview'));
    return FeedbackRequestResult(feedbackSent: asBool(map['feedbackSent']));
  }
}

class YsdkLeaderboardsClient {
  const YsdkLeaderboardsClient(this._module);

  final Object? _module;

  Future<LeaderboardDescriptionModel> getDescription(
    final String leaderboardName,
  ) async {
    final map = asMap(
      await jsCallPromise(_module, 'getDescription', <Object?>[
        leaderboardName,
      ]),
    );
    return _parseLeaderboardDescription(map);
  }

  Future<LeaderboardEntriesDataModel> getEntries(
    final String leaderboardName, {
    final bool? includeUser,
    final int? quantityAround,
    final int? quantityTop,
  }) async {
    final opts = <String, Object?>{};
    if (includeUser != null) {
      opts['includeUser'] = includeUser;
    }
    if (quantityAround != null) {
      opts['quantityAround'] = quantityAround;
    }
    if (quantityTop != null) {
      opts['quantityTop'] = quantityTop;
    }

    final args = <Object?>[leaderboardName];
    if (opts.isNotEmpty) {
      args.add(jsify(opts));
    }

    final map = asMap(await jsCallPromise(_module, 'getEntries', args));
    return _parseLeaderboardEntriesData(map);
  }

  Future<LeaderboardEntryModel> getPlayerEntry(
    final String leaderboardName,
  ) async {
    final map = asMap(
      await jsCallPromise(_module, 'getPlayerEntry', <Object?>[
        leaderboardName,
      ]),
    );
    return _parseLeaderboardEntry(map);
  }

  Future<void> setScore(
    final String leaderboardName,
    final int score, {
    final String? extraData,
  }) async {
    await jsCallPromise(_module, 'setScore', <Object?>[
      leaderboardName,
      score,
      ?extraData,
    ]);
  }
}

class YsdkLegacyLeaderboardsClient {
  const YsdkLegacyLeaderboardsClient(this._module);

  final Object? _module;

  Future<LeaderboardDescriptionModel> getLeaderboardDescription(
    final String leaderboardName,
  ) async {
    final map = asMap(
      await jsCallPromise(_module, 'getLeaderboardDescription', <Object?>[
        leaderboardName,
      ]),
    );
    return _parseLeaderboardDescription(map);
  }

  Future<LeaderboardEntriesDataModel> getLeaderboardEntries(
    final String leaderboardName,
  ) async {
    final map = asMap(
      await jsCallPromise(_module, 'getLeaderboardEntries', <Object?>[
        leaderboardName,
      ]),
    );
    return _parseLeaderboardEntriesData(map);
  }

  Future<LeaderboardEntryModel> getLeaderboardPlayerEntry(
    final String leaderboardName,
  ) async {
    final map = asMap(
      await jsCallPromise(_module, 'getLeaderboardPlayerEntry', <Object?>[
        leaderboardName,
      ]),
    );
    return _parseLeaderboardEntry(map);
  }

  Future<void> setLeaderboardScore(
    final String leaderboardName,
    final int score, {
    final String? extraData,
  }) async {
    await jsCallPromise(_module, 'setLeaderboardScore', <Object?>[
      leaderboardName,
      score,
      ?extraData,
    ]);
  }
}

class YsdkPaymentsClient {
  const YsdkPaymentsClient(this._module, {required this.signed});

  final Object? _module;
  final bool signed;

  Future<void> consumePurchase(final String token) async {
    await jsCallPromise(_module, 'consumePurchase', <Object?>[token]);
  }

  Future<List<ProductModel>> getCatalog() async {
    final list = asList(await jsCallPromise(_module, 'getCatalog'));
    return list.map(asMap).map(ProductModel.fromMap).toList(growable: false);
  }

  Future<List<PurchaseModel>> getPurchasesUnsigned() async {
    final list = asList(await jsCallPromise(_module, 'getPurchases'));
    return list.map(asMap).map(PurchaseModel.fromMap).toList(growable: false);
  }

  Future<SignatureModel> getPurchasesSigned() async {
    final map = asMap(await jsCallPromise(_module, 'getPurchases'));
    return SignatureModel.fromMap(map);
  }

  Future<PurchaseModel> purchaseUnsigned({
    required final String id,
    final String? developerPayload,
  }) async {
    final result = await jsCallPromise(_module, 'purchase', <Object?>[
      jsify(<String, Object?>{'id': id, 'developerPayload': ?developerPayload}),
    ]);
    return PurchaseModel.fromMap(asMap(result));
  }

  Future<SignatureModel> purchaseSigned({
    required final String id,
    final String? developerPayload,
  }) async {
    final result = await jsCallPromise(_module, 'purchase', <Object?>[
      jsify(<String, Object?>{'id': id, 'developerPayload': ?developerPayload}),
    ]);
    return SignatureModel.fromMap(asMap(result));
  }
}

class YsdkShortcutClient {
  const YsdkShortcutClient(this._module);

  final Object? _module;

  Future<ShortcutPromptAvailability> canShowPrompt() async {
    final map = asMap(await jsCallPromise(_module, 'canShowPrompt'));
    return ShortcutPromptAvailability(canShow: asBool(map['canShow']));
  }

  Future<ShortcutPromptResult> showPrompt() async {
    final map = asMap(await jsCallPromise(_module, 'showPrompt'));
    return ShortcutPromptResult(
      outcome: PromptOutcome.fromValue(asString(map['outcome'])),
    );
  }
}

class YsdkScreenClient {
  const YsdkScreenClient(this._module);

  final Object? _module;

  YsdkFullscreenClient get fullscreen =>
      YsdkFullscreenClient(prop(_module, 'fullscreen'));
}

class YsdkFullscreenClient {
  const YsdkFullscreenClient(this._module);

  final Object? _module;

  String get status => asString(prop(_module, 'status'));

  Future<void> request() async {
    await jsCallPromise(_module, 'request');
  }

  Future<void> exit() async {
    await jsCallPromise(_module, 'exit');
  }
}

class YsdkMultiplayerClient {
  const YsdkMultiplayerClient(this._module);

  final Object? _module;

  YsdkMultiplayerSessionsClient get sessions =>
      YsdkMultiplayerSessionsClient(prop(_module, 'sessions'));
}

class YsdkMultiplayerSessionsClient {
  const YsdkMultiplayerSessionsClient(this._module);

  final Object? _module;

  void commit(final MultiplayerCommitPayloadModel payload) {
    jsCall(_module, 'commit', <Object?>[jsify(payload.toJson())]);
  }

  Future<List<MultiplayerSessionOpponentModel>> init({
    final MultiplayerInitOptionsModel? options,
  }) async {
    final list = asList(
      await jsCallPromise(
        _module,
        'init',
        options == null
            ? const <Object?>[]
            : <Object?>[jsify(options.toJson())],
      ),
    );

    return list
        .map((final item) {
          final map = asMap(item);
          final tx = asList(map['transactions'])
              .map((final txItem) {
                final txMap = asMap(txItem);
                return MultiplayerCommitPayloadModel(
                  data: asMap(txMap['data']),
                  time: asInt(txMap['time']),
                );
              })
              .toList(growable: false);

          final metaMap = asMap(map['meta']);
          return MultiplayerSessionOpponentModel(
            id: asString(map['id']),
            meta: MultiplayerMetaModel(
              meta1: asInt(metaMap['meta1']),
              meta2: asInt(metaMap['meta2']),
              meta3: asInt(metaMap['meta3']),
            ),
            transactions: tx,
          );
        })
        .toList(growable: false);
  }

  Future<CallbackBaseMessageDataModel> push(
    final MultiplayerMetaModel meta,
  ) async {
    final map = asMap(
      await jsCallPromise(_module, 'push', <Object?>[jsify(meta.toJson())]),
    );

    final errorMap = asMap(map['error']);
    return CallbackBaseMessageDataModel(
      status: asString(map['status']),
      data: map['data'],
      error: errorMap.isEmpty ? null : asString(errorMap['message']),
    );
  }
}

class YsdkPlayer {
  const YsdkPlayer(this._raw);

  final Object? _raw;

  Future<Map<String, Object?>> getData([final List<String>? keys]) async {
    final result = await jsCallPromise(
      _raw,
      'getData',
      keys == null ? const <Object?>[] : <Object?>[jsify(keys)],
    );
    return asMap(result);
  }

  Future<List<Map<String, Object?>>> getIdsPerGame() async {
    final result = asList(await jsCallPromise(_raw, 'getIDsPerGame'));
    return result.map(asMap).toList(growable: false);
  }

  String getMode() => asString(jsCall(_raw, 'getMode', const <Object?>[]));

  String getName() => asString(jsCall(_raw, 'getName', const <Object?>[]));

  String getPayingStatus() =>
      asString(jsCall(_raw, 'getPayingStatus', const <Object?>[]));

  String getPhoto(final String size) =>
      asString(jsCall(_raw, 'getPhoto', <Object?>[size]));

  Future<Map<String, Object?>> getStats([final List<String>? keys]) async {
    final result = await jsCallPromise(
      _raw,
      'getStats',
      keys == null ? const <Object?>[] : <Object?>[jsify(keys)],
    );
    return asMap(result);
  }

  String getUniqueId() =>
      asString(jsCall(_raw, 'getUniqueID', const <Object?>[]));

  Future<Map<String, Object?>> incrementStats(
    final Map<String, num> stats,
  ) async {
    final result = await jsCallPromise(_raw, 'incrementStats', <Object?>[
      jsify(stats),
    ]);
    return asMap(result);
  }

  bool isAuthorized() =>
      asBool(jsCall(_raw, 'isAuthorized', const <Object?>[]));

  Future<void> setData(final Object? data, {final bool flush = false}) async {
    await jsCallPromise(_raw, 'setData', <Object?>[data, flush]);
  }

  Future<void> setStats(final Map<String, num> stats) async {
    await jsCallPromise(_raw, 'setStats', <Object?>[jsify(stats)]);
  }
}

class YsdkDeviceInfo {
  const YsdkDeviceInfo(this._raw);

  final Object? _raw;

  bool isDesktop() => asBool(jsCall(_raw, 'isDesktop', const <Object?>[]));
  bool isMobile() => asBool(jsCall(_raw, 'isMobile', const <Object?>[]));
  bool isTv() => asBool(jsCall(_raw, 'isTV', const <Object?>[]));
  bool isTablet() => asBool(jsCall(_raw, 'isTablet', const <Object?>[]));
  DeviceType get type => DeviceType.fromValue(asString(prop(_raw, 'type')));
}

class YsdkEnvironment {
  const YsdkEnvironment(this._raw);

  final Object? _raw;

  String get appId => asString(asMap(prop(_raw, 'app'))['id']);
  String get browserLang => asString(asMap(prop(_raw, 'browser'))['lang']);
  ISO_639_1 get i18nLang =>
      ISO_639_1.fromValue(asString(asMap(prop(_raw, 'i18n'))['lang']));
  TopLevelDomain get i18nTld =>
      TopLevelDomain.fromValue(asString(asMap(prop(_raw, 'i18n'))['tld']));
  String? get payload {
    final value = prop(_raw, 'payload');
    if (value == null) {
      return null;
    }
    final result = asString(value);
    return result.isEmpty ? null : result;
  }
}

LeaderboardDescriptionModel _parseLeaderboardDescription(
  final Map<String, Object?> map,
) {
  final descriptionMap = asMap(map['description']);
  final scoreFormatMap = asMap(descriptionMap['score_format']);
  final optionsMap = asMap(scoreFormatMap['options']);

  return LeaderboardDescriptionModel(
    appId: asString(map['appID']),
    isDefault: asBool(map['default']),
    name: asString(map['name']),
    type: asString(descriptionMap['type']),
    invertSortOrder: asBool(descriptionMap['invert_sort_order']),
    decimalOffset: asInt(optionsMap['decimal_offset']),
    title: asMap(
      map['title'],
    ).map((final key, final value) => MapEntry(key, asString(value))),
  );
}

LeaderboardEntriesDataModel _parseLeaderboardEntriesData(
  final Map<String, Object?> map,
) {
  final entries = asList(
    map['entries'],
  ).map(asMap).map(_parseLeaderboardEntry).toList(growable: false);

  return LeaderboardEntriesDataModel(
    entries: entries,
    leaderboard: _parseLeaderboardDescription(asMap(map['leaderboard'])),
    userRank: asInt(map['userRank']),
  );
}

LeaderboardEntryModel _parseLeaderboardEntry(final Map<String, Object?> map) {
  final playerMap = asMap(map['player']);
  final permissionsMap = asMap(playerMap['scopePermissions']);

  return LeaderboardEntryModel(
    extraData: map['extraData'] as String?,
    formattedScore: asString(map['formattedScore']),
    player: LeaderboardPlayerModel(
      lang: asString(playerMap['lang']),
      publicName: asString(playerMap['publicName']),
      uniqueId: asString(playerMap['uniqueID']),
      scopePermissions: permissionsMap.map(
        (final key, final value) => MapEntry(key, asString(value)),
      ),
    ),
    rank: asInt(map['rank']),
    score: asInt(map['score']),
  );
}
