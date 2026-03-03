@TestOn('browser')
library;

import 'dart:js_util' as js_util;

import 'package:test/test.dart';
import 'package:xsoulspace_ysdk_games_js/src/wrapper/yandex_games_web.dart';

late final _SdkStubState _sdkStub;

void main() {
  setUpAll(() {
    _sdkStub = _SdkStubState()..install();
  });

  setUp(() => _sdkStub.reset());

  test('availability probe', () {
    expect(YandexGames.isAvailable(), isTrue);
    expect(
      YandexGames.isAvailable(expectedGlobal: 'MissingYsdkGlobal'),
      isFalse,
    );
  });

  test('core entrypoint and common APIs', () async {
    final ysdk = await YandexGames.init();

    expect(_sdkStub.initCalls, 1);
    expect(_sdkStub.lastInitSigned, isFalse);

    final flags = await ysdk.getFlags(
      clientFeatures: const <ClientFeatureModel>[
        ClientFeatureModel(name: 'exp', value: 'on'),
      ],
      defaultFlags: <String, String>{'base': '1'},
    );

    expect(flags, containsPair('base', '1'));
    expect(flags, containsPair('exp', 'on'));
    expect(_sdkStub.lastFlagsClientFeatureNames, equals(<String>['exp']));

    await ysdk.dispatchEvent(
      SdkEventName.exit,
      detail: <String, Object?>{'reason': 'quit'},
    );
    expect(_sdkStub.lastDispatchEvent, 'EXIT');
    expect(_sdkStub.lastDispatchDetail, containsPair('reason', 'quit'));

    final storage = _asMap(await ysdk.getStorage());
    expect(storage, containsPair('slot', 'main'));

    expect(await ysdk.isAvailableMethod('known.method'), isTrue);
    expect(await ysdk.isAvailableMethod('unknown.method'), isFalse);

    expect(ysdk.serverTime(), 12345);

    expect(ysdk.deviceInfo.isDesktop(), isTrue);
    expect(ysdk.deviceInfo.isMobile(), isFalse);
    expect(ysdk.deviceInfo.isTv(), isFalse);
    expect(ysdk.deviceInfo.isTablet(), isFalse);
    expect(ysdk.deviceInfo.type, DeviceType.desktop);

    expect(ysdk.environment.appId, 'app-id');
    expect(ysdk.environment.browserLang, 'en');
    expect(ysdk.environment.i18nLang, ISO_639_1.ru);
    expect(ysdk.environment.i18nTld, TopLevelDomain.ru);
    expect(ysdk.environment.payload, 'payload-1');
  });

  test('adv auth clipboard and features wrappers', () async {
    final ysdk = await YandexGames.init();

    final status = await ysdk.adv.getBannerAdvStatus();
    expect(status.stickyAdvIsShowing, isFalse);
    expect(status.reason, StickyAdvError.adv_is_not_connected);

    final showResult = await ysdk.adv.showBannerAdv();
    expect(showResult.reason, StickyAdvError.unknown);

    final hideResult = await ysdk.adv.hideBannerAdv();
    expect(hideResult.stickyAdvIsShowing, isFalse);

    var fullscreenOpen = false;
    bool? fullscreenCloseWasShown;
    var fullscreenOffline = false;
    Object? fullscreenError;
    ysdk.adv.showFullscreenAdv(
      callbacks: FullscreenAdvCallbacks(
        onOpen: () => fullscreenOpen = true,
        onClose: (final wasShown) => fullscreenCloseWasShown = wasShown,
        onOffline: () => fullscreenOffline = true,
        onError: (final error) => fullscreenError = error,
      ),
    );
    expect(_sdkStub.fullscreenAdvCalls, 1);
    expect(fullscreenOpen, isTrue);
    expect(fullscreenCloseWasShown, isTrue);
    expect(fullscreenOffline, isTrue);
    expect(fullscreenError, 'fullscreen-error');

    var rewardedOpen = false;
    var rewardedClose = false;
    var rewardedDone = false;
    Object? rewardedError;
    ysdk.adv.showRewardedVideo(
      callbacks: RewardedVideoCallbacks(
        onOpen: () => rewardedOpen = true,
        onClose: () => rewardedClose = true,
        onRewarded: () => rewardedDone = true,
        onError: (final error) => rewardedError = error,
      ),
    );
    expect(_sdkStub.rewardedVideoCalls, 1);
    expect(rewardedOpen, isTrue);
    expect(rewardedClose, isTrue);
    expect(rewardedDone, isTrue);
    expect(rewardedError, 'rewarded-error');

    await ysdk.auth.openAuthDialog();
    expect(_sdkStub.authDialogCalls, 1);

    ysdk.clipboard.writeText('copied');
    expect(_sdkStub.lastClipboardText, 'copied');

    ysdk.features.gameplay.start();
    ysdk.features.gameplay.stop();
    ysdk.features.loading.ready();
    expect(_sdkStub.gameplayStartCalls, 1);
    expect(_sdkStub.gameplayStopCalls, 1);
    expect(_sdkStub.loadingReadyCalls, 1);

    final games = await ysdk.features.games.getAllGames();
    expect(games.developerUrl, 'dev-url');
    expect(games.games, hasLength(1));
    expect(games.games.first.appId, 'app-1');

    final gameById = await ysdk.features.games.getGameById(42);
    expect(_sdkStub.lastGameByIdRequest, 42);
    expect(gameById.isAvailable, isTrue);
    expect(gameById.game?.appId, 'app-42');
  });

  test('feedback shortcut and screen wrappers', () async {
    final ysdk = await YandexGames.init();

    final canReview = await ysdk.feedback.canReview();
    expect(canReview.value, isFalse);
    expect(canReview.reason, FeedbackError.no_auth);

    final reviewResult = await ysdk.feedback.requestReview();
    expect(reviewResult.feedbackSent, isTrue);

    final canShowPrompt = await ysdk.shortcut.canShowPrompt();
    expect(canShowPrompt.canShow, isTrue);

    final promptResult = await ysdk.shortcut.showPrompt();
    expect(promptResult.outcome, PromptOutcome.rejected);

    expect(ysdk.screen.fullscreen.status, 'off');
    await ysdk.screen.fullscreen.request();
    await ysdk.screen.fullscreen.exit();
    expect(_sdkStub.fullscreenRequestCalls, 1);
    expect(_sdkStub.fullscreenExitCalls, 1);
  });

  test('leaderboards wrappers and legacy leaderboards wrappers', () async {
    final ysdk = await YandexGames.init();

    final description = await ysdk.leaderboards.getDescription('lb-main');
    expect(description.appId, 'app-1');
    expect(description.isDefault, isTrue);
    expect(description.name, 'lb-main');
    expect(description.type, 'numeric');
    expect(description.invertSortOrder, isFalse);
    expect(description.decimalOffset, 2);
    expect(description.title, containsPair('en', 'Leaderboard'));

    final entries = await ysdk.leaderboards.getEntries(
      'lb-main',
      includeUser: true,
      quantityAround: 2,
      quantityTop: 3,
    );
    expect(_sdkStub.lastLeaderboardEntriesName, 'lb-main');
    expect(
      _sdkStub.lastLeaderboardEntriesOptions,
      containsPair('includeUser', true),
    );
    expect(entries.userRank, 5);
    expect(entries.entries, hasLength(1));
    expect(entries.entries.first.player.uniqueId, 'player-1');
    expect(entries.entries.first.rank, 1);

    final playerEntry = await ysdk.leaderboards.getPlayerEntry('lb-main');
    expect(playerEntry.player.publicName, 'Player One');

    await ysdk.leaderboards.setScore('lb-main', 999, extraData: 'meta');
    expect(_sdkStub.lastSetScore, containsPair('name', 'lb-main'));
    expect(_sdkStub.lastSetScore, containsPair('score', 999));
    expect(_sdkStub.lastSetScore, containsPair('extraData', 'meta'));

    final legacy = await ysdk.getLegacyLeaderboards();
    final legacyDescription = await legacy.getLeaderboardDescription('lb-main');
    expect(legacyDescription.name, 'lb-main');

    final legacyEntries = await legacy.getLeaderboardEntries('lb-main');
    expect(legacyEntries.entries, hasLength(1));

    final legacyEntry = await legacy.getLeaderboardPlayerEntry('lb-main');
    expect(legacyEntry.player.uniqueId, 'player-1');

    await legacy.setLeaderboardScore('lb-main', 1001, extraData: 'legacy');
    expect(_sdkStub.lastLegacySetScore, containsPair('name', 'lb-main'));
    expect(_sdkStub.lastLegacySetScore, containsPair('score', 1001));
    expect(_sdkStub.lastLegacySetScore, containsPair('extraData', 'legacy'));
  });

  test('payments wrappers for unsigned and signed flows', () async {
    final unsignedClient = await YandexGames.init(signed: false);

    expect(_sdkStub.initCalls, 1);
    expect(_sdkStub.lastInitSigned, isFalse);
    expect(unsignedClient.payments.signed, isFalse);

    final catalog = await unsignedClient.payments.getCatalog();
    expect(catalog, hasLength(1));
    expect(catalog.first.id, 'prod-1');
    expect(catalog.first.price, '\$41');

    final purchasesUnsigned = await unsignedClient.payments
        .getPurchasesUnsigned();
    expect(purchasesUnsigned, hasLength(1));
    expect(purchasesUnsigned.first.productId, 'prod-1');
    expect(purchasesUnsigned.first.developerPayload, 'dp-1');

    final purchaseUnsigned = await unsignedClient.payments.purchaseUnsigned(
      id: 'prod-1',
      developerPayload: 'dp-2',
    );
    expect(_sdkStub.lastUnsignedPurchaseOptions, containsPair('id', 'prod-1'));
    expect(
      _sdkStub.lastUnsignedPurchaseOptions,
      containsPair('developerPayload', 'dp-2'),
    );
    expect(purchaseUnsigned.purchaseToken, 'token-2');
    expect(purchaseUnsigned.developerPayload, 'dp-2');

    await unsignedClient.payments.consumePurchase('consume-token');
    expect(_sdkStub.lastConsumedToken, 'consume-token');

    final paymentsSigned = await unsignedClient.getPaymentsSigned();
    expect(paymentsSigned.signed, isTrue);
    final signedPurchases = await paymentsSigned.getPurchasesSigned();
    expect(signedPurchases.signature, 'signed-purchases');

    final signedPurchase = await paymentsSigned.purchaseSigned(id: 'prod-1');
    expect(signedPurchase.signature, 'signed-purchase');

    final paymentsUnsigned = await unsignedClient.getPaymentsUnsigned();
    expect(paymentsUnsigned.signed, isFalse);

    final signedClient = await YandexGames.init(signed: true);
    expect(signedClient.payments.signed, isTrue);
  });

  test('multiplayer wrappers', () async {
    final ysdk = await YandexGames.init();

    ysdk.multiplayer.sessions.commit(
      const MultiplayerCommitPayloadModel(
        data: <String, Object?>{'turn': 1},
        time: 111,
      ),
    );
    expect(_sdkStub.lastMultiplayerCommitPayload, containsPair('time', 111));

    final opponents = await ysdk.multiplayer.sessions.init(
      options: const MultiplayerInitOptionsModel(
        count: 2,
        isEventBased: true,
        maxOpponentTurnTime: 120,
        meta: MultiplayerMetaRangesModel(
          meta1: MultiplayerMetaRangeModel(min: 1, max: 2),
          meta2: MultiplayerMetaRangeModel(min: 3, max: 4),
          meta3: MultiplayerMetaRangeModel(min: 5, max: 6),
        ),
      ),
    );
    expect(_sdkStub.lastMultiplayerInitOptions, containsPair('count', 2));
    expect(opponents, hasLength(1));
    expect(opponents.first.id, 'op-1');
    expect(opponents.first.meta.meta1, 1);
    expect(opponents.first.transactions, hasLength(1));
    expect(opponents.first.transactions.first.data, containsPair('turn', 1));

    final push = await ysdk.multiplayer.sessions.push(
      const MultiplayerMetaModel(meta1: 7, meta2: 8, meta3: 9),
    );
    expect(_sdkStub.lastMultiplayerPushMeta, containsPair('meta1', 7));
    expect(push.status, 'ok');
    expect(push.error, 'already-pushed');
  });

  test('player wrappers for unsigned and signed flows', () async {
    final ysdk = await YandexGames.init();

    final player = await ysdk.getPlayerUnsigned();
    final data = await player.getData(<String>['coins', 'xp']);
    expect(_sdkStub.lastPlayerGetDataKeys, equals(<String>['coins', 'xp']));
    expect(data, containsPair('coins', 99));

    final ids = await player.getIdsPerGame();
    expect(ids, hasLength(1));
    expect(ids.first, containsPair('id', 'game-1'));

    expect(player.getMode(), 'lite');
    expect(player.getName(), 'Player One');
    expect(player.getPayingStatus(), 'unknown');
    expect(player.getPhoto('small'), 'photo-small');
    expect(player.getUniqueId(), 'player-1');
    expect(player.isAuthorized(), isTrue);

    final stats = await player.getStats(<String>['score']);
    expect(_sdkStub.lastPlayerGetStatsKeys, equals(<String>['score']));
    expect(stats, containsPair('score', 10));

    final incremented = await player.incrementStats(<String, num>{'score': 3});
    expect(_sdkStub.lastPlayerIncrementStats, containsPair('score', 3));
    expect(incremented, containsPair('score', 13));

    await player.setData(<String, Object?>{'volume': 7}, flush: true);
    expect(_sdkStub.lastPlayerSetData, containsPair('volume', 7));
    expect(_sdkStub.lastPlayerSetDataFlush, isTrue);

    await player.setStats(<String, num>{'score': 100});
    expect(_sdkStub.lastPlayerSetStats, containsPair('score', 100));

    final signature = await ysdk.getPlayerSigned();
    expect(signature.signature, 'signed-player');
  });
}

class _SdkStubState {
  int initCalls = 0;
  bool? lastInitSigned;
  String? lastDispatchEvent;
  Map<String, Object?> lastDispatchDetail = <String, Object?>{};
  List<String> lastFlagsClientFeatureNames = <String>[];
  String? lastClipboardText;
  int authDialogCalls = 0;
  int gameplayStartCalls = 0;
  int gameplayStopCalls = 0;
  int loadingReadyCalls = 0;
  int fullscreenAdvCalls = 0;
  int rewardedVideoCalls = 0;
  int fullscreenRequestCalls = 0;
  int fullscreenExitCalls = 0;
  int lastGameByIdRequest = -1;
  String? lastConsumedToken;
  Map<String, Object?> lastUnsignedPurchaseOptions = <String, Object?>{};
  String? lastLeaderboardEntriesName;
  Map<String, Object?> lastLeaderboardEntriesOptions = <String, Object?>{};
  Map<String, Object?> lastSetScore = <String, Object?>{};
  Map<String, Object?> lastLegacySetScore = <String, Object?>{};
  Map<String, Object?> lastMultiplayerCommitPayload = <String, Object?>{};
  Map<String, Object?> lastMultiplayerInitOptions = <String, Object?>{};
  Map<String, Object?> lastMultiplayerPushMeta = <String, Object?>{};
  List<String> lastPlayerGetDataKeys = <String>[];
  List<String> lastPlayerGetStatsKeys = <String>[];
  Map<String, Object?> lastPlayerIncrementStats = <String, Object?>{};
  Map<String, Object?> lastPlayerSetData = <String, Object?>{};
  bool lastPlayerSetDataFlush = false;
  Map<String, Object?> lastPlayerSetStats = <String, Object?>{};

  void reset() {
    initCalls = 0;
    lastInitSigned = null;
    lastDispatchEvent = null;
    lastDispatchDetail = <String, Object?>{};
    lastFlagsClientFeatureNames = <String>[];
    lastClipboardText = null;
    authDialogCalls = 0;
    gameplayStartCalls = 0;
    gameplayStopCalls = 0;
    loadingReadyCalls = 0;
    fullscreenAdvCalls = 0;
    rewardedVideoCalls = 0;
    fullscreenRequestCalls = 0;
    fullscreenExitCalls = 0;
    lastGameByIdRequest = -1;
    lastConsumedToken = null;
    lastUnsignedPurchaseOptions = <String, Object?>{};
    lastLeaderboardEntriesName = null;
    lastLeaderboardEntriesOptions = <String, Object?>{};
    lastSetScore = <String, Object?>{};
    lastLegacySetScore = <String, Object?>{};
    lastMultiplayerCommitPayload = <String, Object?>{};
    lastMultiplayerInitOptions = <String, Object?>{};
    lastMultiplayerPushMeta = <String, Object?>{};
    lastPlayerGetDataKeys = <String>[];
    lastPlayerGetStatsKeys = <String>[];
    lastPlayerIncrementStats = <String, Object?>{};
    lastPlayerSetData = <String, Object?>{};
    lastPlayerSetDataFlush = false;
    lastPlayerSetStats = <String, Object?>{};
  }

  void install() {
    reset();

    Object? jsPromise(final Object? value) => value;

    final player = js_util.jsify(<String, Object?>{
      'getData': js_util.allowInterop(([final Object? keys]) {
        lastPlayerGetDataKeys = _asStringList(keys);
        return jsPromise(<String, Object?>{'coins': 99, 'xp': 7});
      }),
      'getIDsPerGame': js_util.allowInterop(
        () => jsPromise(<Object?>[
          <String, Object?>{'id': 'game-1'},
        ]),
      ),
      'getMode': js_util.allowInterop(() => 'lite'),
      'getName': js_util.allowInterop(() => 'Player One'),
      'getPayingStatus': js_util.allowInterop(() => 'unknown'),
      'getPhoto': js_util.allowInterop((final String size) => 'photo-$size'),
      'getStats': js_util.allowInterop(([final Object? keys]) {
        lastPlayerGetStatsKeys = _asStringList(keys);
        return jsPromise(<String, Object?>{'score': 10});
      }),
      'getUniqueID': js_util.allowInterop(() => 'player-1'),
      'incrementStats': js_util.allowInterop((final Object? stats) {
        lastPlayerIncrementStats = _asMap(stats);
        return jsPromise(<String, Object?>{'score': 13});
      }),
      'isAuthorized': js_util.allowInterop(() => true),
      'setData': js_util.allowInterop((
        final Object? data, [
        final bool flush = false,
      ]) {
        lastPlayerSetData = _asMap(data);
        lastPlayerSetDataFlush = flush;
        return jsPromise(null);
      }),
      'setStats': js_util.allowInterop((final Object? stats) {
        lastPlayerSetStats = _asMap(stats);
        return jsPromise(null);
      }),
    });

    final unsignedPayments = js_util.jsify(<String, Object?>{
      'consumePurchase': js_util.allowInterop((final String token) {
        lastConsumedToken = token;
        return jsPromise(null);
      }),
      'getCatalog': js_util.allowInterop(
        () => jsPromise(<Object?>[
          <String, Object?>{
            'description': 'desc',
            'id': 'prod-1',
            'imageURI': 'image',
            'price': '\$41',
            'priceCurrencyCode': 'USD',
            'priceValue': '41',
            'title': 'Product 1',
          },
        ]),
      ),
      'getPurchases': js_util.allowInterop(
        () => jsPromise(<Object?>[
          <String, Object?>{
            'productID': 'prod-1',
            'purchaseToken': 'token-1',
            'developerPayload': 'dp-1',
          },
        ]),
      ),
      'purchase': js_util.allowInterop((final Object? opts) {
        lastUnsignedPurchaseOptions = _asMap(opts);
        return jsPromise(<String, Object?>{
          'productID': 'prod-1',
          'purchaseToken': 'token-2',
          'developerPayload': lastUnsignedPurchaseOptions['developerPayload']
              ?.toString(),
        });
      }),
    });

    final signedPayments = js_util.jsify(<String, Object?>{
      'consumePurchase': js_util.allowInterop((final String token) {
        lastConsumedToken = token;
        return jsPromise(null);
      }),
      'getCatalog': js_util.allowInterop(() => jsPromise(<Object?>[])),
      'getPurchases': js_util.allowInterop(
        () => jsPromise(<String, Object?>{'signature': 'signed-purchases'}),
      ),
      'purchase': js_util.allowInterop(
        (final Object? opts) =>
            jsPromise(<String, Object?>{'signature': 'signed-purchase'}),
      ),
    });

    final leaderboardDescription = _leaderboardDescriptionJson();
    final leaderboardEntry = _leaderboardEntryJson();

    final leaderboards = js_util.jsify(<String, Object?>{
      'getDescription': js_util.allowInterop(
        (final String name) => jsPromise(leaderboardDescription),
      ),
      'getEntries': js_util.allowInterop((
        final String name, [
        final Object? opts,
      ]) {
        lastLeaderboardEntriesName = name;
        lastLeaderboardEntriesOptions = _asMap(opts);
        return jsPromise(<String, Object?>{
          'entries': <Object?>[leaderboardEntry],
          'leaderboard': leaderboardDescription,
          'userRank': 5,
        });
      }),
      'getPlayerEntry': js_util.allowInterop(
        (final String name) => jsPromise(leaderboardEntry),
      ),
      'setScore': js_util.allowInterop((
        final String name,
        final int score, [
        final String? extraData,
      ]) {
        lastSetScore = <String, Object?>{
          'name': name,
          'score': score,
          if (extraData != null) 'extraData': extraData,
        };
        return jsPromise(null);
      }),
    });

    final legacyLeaderboards = js_util.jsify(<String, Object?>{
      'getLeaderboardDescription': js_util.allowInterop(
        (final String name) => jsPromise(leaderboardDescription),
      ),
      'getLeaderboardEntries': js_util.allowInterop(
        (final String name) => jsPromise(<String, Object?>{
          'entries': <Object?>[leaderboardEntry],
          'leaderboard': leaderboardDescription,
          'userRank': 2,
        }),
      ),
      'getLeaderboardPlayerEntry': js_util.allowInterop(
        (final String name) => jsPromise(leaderboardEntry),
      ),
      'setLeaderboardScore': js_util.allowInterop((
        final String name,
        final int score, [
        final String? extraData,
      ]) {
        lastLegacySetScore = <String, Object?>{
          'name': name,
          'score': score,
          if (extraData != null) 'extraData': extraData,
        };
        return jsPromise(null);
      }),
    });

    final sdk = js_util.jsify(<String, Object?>{
      'adv': <String, Object?>{
        'getBannerAdvStatus': js_util.allowInterop(
          () => jsPromise(<String, Object?>{
            'stickyAdvIsShowing': false,
            'reason': 'ADV_IS_NOT_CONNECTED',
          }),
        ),
        'showBannerAdv': js_util.allowInterop(
          () => jsPromise(<String, Object?>{'reason': 'UNKNOWN'}),
        ),
        'hideBannerAdv': js_util.allowInterop(
          () => jsPromise(<String, Object?>{'stickyAdvIsShowing': false}),
        ),
        'showFullscreenAdv': js_util.allowInterop(([final Object? opts]) {
          fullscreenAdvCalls += 1;
          final callbacks = opts == null
              ? null
              : js_util.getProperty<Object?>(opts, 'callbacks');
          _callCallback(callbacks, 'onOpen');
          _callCallback(callbacks, 'onClose', true);
          _callCallback(callbacks, 'onOffline');
          _callCallback(callbacks, 'onError', 'fullscreen-error');
        }),
        'showRewardedVideo': js_util.allowInterop(([final Object? opts]) {
          rewardedVideoCalls += 1;
          final callbacks = opts == null
              ? null
              : js_util.getProperty<Object?>(opts, 'callbacks');
          _callCallback(callbacks, 'onOpen');
          _callCallback(callbacks, 'onClose');
          _callCallback(callbacks, 'onRewarded');
          _callCallback(callbacks, 'onError', 'rewarded-error');
        }),
      },
      'auth': <String, Object?>{
        'openAuthDialog': js_util.allowInterop(() {
          authDialogCalls += 1;
          return jsPromise(null);
        }),
      },
      'clipboard': <String, Object?>{
        'writeText': js_util.allowInterop((final String text) {
          lastClipboardText = text;
        }),
      },
      'features': <String, Object?>{
        'GameplayAPI': <String, Object?>{
          'start': js_util.allowInterop(() => gameplayStartCalls += 1),
          'stop': js_util.allowInterop(() => gameplayStopCalls += 1),
        },
        'GamesAPI': <String, Object?>{
          'getAllGames': js_util.allowInterop(
            () => jsPromise(<String, Object?>{
              'developerURL': 'dev-url',
              'games': <Object?>[
                <String, Object?>{
                  'appID': 'app-1',
                  'coverURL': 'cover',
                  'iconURL': 'icon',
                  'title': 'Game One',
                  'url': 'https://example.invalid/game-one',
                },
              ],
            }),
          ),
          'getGameByID': js_util.allowInterop((final int id) {
            lastGameByIdRequest = id;
            return jsPromise(<String, Object?>{
              'isAvailable': true,
              'game': <String, Object?>{
                'appID': 'app-$id',
                'coverURL': 'cover-$id',
                'iconURL': 'icon-$id',
                'title': 'Game $id',
                'url': 'https://example.invalid/game-$id',
              },
            });
          }),
        },
        'LoadingAPI': <String, Object?>{
          'ready': js_util.allowInterop(() => loadingReadyCalls += 1),
        },
      },
      'feedback': <String, Object?>{
        'canReview': js_util.allowInterop(
          () =>
              jsPromise(<String, Object?>{'value': false, 'reason': 'NO_AUTH'}),
        ),
        'requestReview': js_util.allowInterop(
          () => jsPromise(<String, Object?>{'feedbackSent': true}),
        ),
      },
      'leaderboards': leaderboards,
      'multiplayer': <String, Object?>{
        'sessions': <String, Object?>{
          'commit': js_util.allowInterop((final Object? payload) {
            lastMultiplayerCommitPayload = _asMap(payload);
          }),
          'init': js_util.allowInterop(([final Object? opts]) {
            lastMultiplayerInitOptions = _asMap(opts);
            return jsPromise(<Object?>[
              <String, Object?>{
                'id': 'op-1',
                'meta': <String, Object?>{'meta1': 1, 'meta2': 2, 'meta3': 3},
                'transactions': <Object?>[
                  <String, Object?>{
                    'data': <String, Object?>{'turn': 1},
                    'time': 100,
                  },
                ],
              },
            ]);
          }),
          'push': js_util.allowInterop((final Object? meta) {
            lastMultiplayerPushMeta = _asMap(meta);
            return jsPromise(<String, Object?>{
              'status': 'ok',
              'data': <String, Object?>{'accepted': true},
              'error': <String, Object?>{'message': 'already-pushed'},
            });
          }),
        },
      },
      'payments': unsignedPayments,
      'screen': <String, Object?>{
        'fullscreen': <String, Object?>{
          'status': 'off',
          'request': js_util.allowInterop(() {
            fullscreenRequestCalls += 1;
            return jsPromise(null);
          }),
          'exit': js_util.allowInterop(() {
            fullscreenExitCalls += 1;
            return jsPromise(null);
          }),
        },
      },
      'shortcut': <String, Object?>{
        'canShowPrompt': js_util.allowInterop(
          () => jsPromise(<String, Object?>{'canShow': true}),
        ),
        'showPrompt': js_util.allowInterop(
          () => jsPromise(<String, Object?>{'outcome': 'rejected'}),
        ),
      },
      'deviceInfo': <String, Object?>{
        'isDesktop': js_util.allowInterop(() => true),
        'isMobile': js_util.allowInterop(() => false),
        'isTV': js_util.allowInterop(() => false),
        'isTablet': js_util.allowInterop(() => false),
        'type': 'desktop',
      },
      'environment': <String, Object?>{
        'app': <String, Object?>{'id': 'app-id'},
        'browser': <String, Object?>{'lang': 'en'},
        'i18n': <String, Object?>{'lang': 'ru', 'tld': 'ru'},
        'payload': 'payload-1',
      },
      'dispatchEvent': js_util.allowInterop((
        final String event, [
        final Object? detail,
      ]) {
        lastDispatchEvent = event;
        lastDispatchDetail = _asMap(detail);
        return jsPromise(null);
      }),
      'getFlags': js_util.allowInterop(([final Object? params]) {
        final decoded = _asMap(params);
        final defaults = _asMap(decoded['defaultFlags']);
        final features = _asList(
          decoded['clientFeatures'],
        ).map(_asMap).toList();
        lastFlagsClientFeatureNames = features
            .map((final feature) => feature['name']?.toString() ?? '')
            .where((final name) => name.isNotEmpty)
            .toList(growable: false);

        final result = <String, Object?>{};
        for (final entry in defaults.entries) {
          result[entry.key] = entry.value?.toString() ?? '';
        }
        for (final feature in features) {
          final name = feature['name']?.toString();
          final value = feature['value']?.toString();
          if (name != null && value != null) {
            result[name] = value;
          }
        }
        return jsPromise(result);
      }),
      'getLeaderboards': js_util.allowInterop(
        () => jsPromise(legacyLeaderboards),
      ),
      'getPayments': js_util.allowInterop(([final Object? opts]) {
        final signed = _asMap(opts)['signed'] == true;
        return jsPromise(signed ? signedPayments : unsignedPayments);
      }),
      'getPlayer': js_util.allowInterop(([final Object? opts]) {
        final signed = _asMap(opts)['signed'] == true;
        if (signed) {
          return jsPromise(<String, Object?>{'signature': 'signed-player'});
        }
        return jsPromise(player);
      }),
      'getStorage': js_util.allowInterop(
        () => jsPromise(<String, Object?>{'slot': 'main'}),
      ),
      'isAvailableMethod': js_util.allowInterop(
        (final String name) => jsPromise(name == 'known.method'),
      ),
      'serverTime': js_util.allowInterop(() => 12345),
    });

    final yaGames = js_util.jsify(<String, Object?>{
      'init': js_util.allowInterop(([final Object? opts]) {
        initCalls += 1;
        lastInitSigned = _asMap(opts)['signed'] == true;
        return jsPromise(sdk);
      }),
    });

    js_util.setProperty(js_util.globalThis, 'YaGames', yaGames);
  }
}

Map<String, Object?> _leaderboardDescriptionJson() => <String, Object?>{
  'appID': 'app-1',
  'default': true,
  'name': 'lb-main',
  'description': <String, Object?>{
    'type': 'numeric',
    'invert_sort_order': false,
    'score_format': <String, Object?>{
      'options': <String, Object?>{'decimal_offset': 2},
    },
  },
  'title': <String, Object?>{'en': 'Leaderboard'},
};

Map<String, Object?> _leaderboardEntryJson() => <String, Object?>{
  'extraData': 'meta',
  'formattedScore': '1000',
  'player': <String, Object?>{
    'lang': 'en',
    'publicName': 'Player One',
    'uniqueID': 'player-1',
    'scopePermissions': <String, Object?>{'avatar': 'allow'},
  },
  'rank': 1,
  'score': 1000,
};

void _callCallback(
  final Object? callbacks,
  final String name, [
  final Object? arg,
]) {
  if (callbacks == null) {
    return;
  }
  final callback = js_util.getProperty<Object?>(callbacks, name);
  if (callback == null) {
    return;
  }

  if (arg == null) {
    js_util.callMethod<Object?>(callback, 'call', <Object?>[null]);
    return;
  }

  js_util.callMethod<Object?>(callback, 'call', <Object?>[null, arg]);
}

Map<String, Object?> _asMap(final Object? value) {
  if (value == null) {
    return <String, Object?>{};
  }
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map<Object?, Object?>) {
    return value.cast<String, Object?>();
  }

  final dartified = js_util.dartify(value);
  if (dartified is Map<String, Object?>) {
    return dartified;
  }
  if (dartified is Map<Object?, Object?>) {
    return dartified.cast<String, Object?>();
  }
  return <String, Object?>{};
}

List<Object?> _asList(final Object? value) {
  if (value == null) {
    return <Object?>[];
  }
  if (value is List<Object?>) {
    return value;
  }
  if (value is List<dynamic>) {
    return value.cast<Object?>();
  }

  final dartified = js_util.dartify(value);
  if (dartified is List<Object?>) {
    return dartified;
  }
  if (dartified is List<dynamic>) {
    return dartified.cast<Object?>();
  }
  return <Object?>[];
}

List<String> _asStringList(final Object? value) =>
    _asList(value).map((final item) => item?.toString() ?? '').toList();
