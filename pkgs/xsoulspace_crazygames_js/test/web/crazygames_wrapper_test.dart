@TestOn('browser')
library;

import 'dart:js_util' as js_util;

import 'package:test/test.dart';
import 'package:xsoulspace_crazygames_js/src/wrapper/crazy_games_web.dart';
import 'package:xsoulspace_crazygames_js/src/wrapper/models.dart';

late final _SdkStubState _stub;

void main() {
  setUpAll(() {
    _stub = _SdkStubState()..install();
  });

  setUp(() => _stub.reset());

  test('availability probe', () {
    expect(CrazyGames.isAvailable(), isTrue);
    expect(
      CrazyGames.isAvailable(expectedGlobal: 'MissingCrazyGamesGlobal'),
      isFalse,
    );
  });

  test('init + environment', () async {
    final cg = await CrazyGames.init();
    expect(_stub.initCalls, 1);
    expect(cg.environment, Environment.crazygames);
    expect(cg.isQaTool, isFalse);
  });

  test('ad + banner + game + user + data + analytics', () async {
    final cg = await CrazyGames.init();

    var adStarted = false;
    var adFinished = false;
    SdkError? adError;
    await cg.ad.requestAd(
      AdType.midgame,
      adStarted: () => adStarted = true,
      adFinished: () => adFinished = true,
      adError: (final error) => adError = error,
    );
    expect(_stub.lastAdType, 'midgame');
    expect(adStarted, isTrue);
    expect(adFinished, isTrue);
    expect(adError, isNull);

    cg.ad.prefetchAd(AdType.rewarded);
    expect(_stub.prefetchedAdTypes, contains('rewarded'));
    expect(await cg.ad.hasAdblock(), isTrue);

    AdblockPopupState? popupState;
    final adblockListener = cg.ad.addAdblockPopupListener((final state) {
      popupState = state;
    });
    _stub.emitAdblockPopup('open');
    expect(popupState, AdblockPopupState.open);
    cg.ad.removeAdblockPopupListener(adblockListener);
    expect(cg.ad.isAdPlaying, isFalse);

    final prefetched = await cg.banner.prefetchBanner(
      const BannerRequest(id: 'banner-prefetch', width: 300, height: 250),
    );
    expect(prefetched.id, 'banner-prefetch');

    await cg.banner.requestBanner(
      const BannerRequest(id: 'banner-1', width: 300, height: 250),
    );
    expect(_stub.lastBannerRequest, containsPair('id', 'banner-1'));

    final prefetchedResponsive = await cg.banner.prefetchResponsiveBanner(
      const BannerRequest(id: 'banner-2', width: 728, height: 90),
    );
    expect(prefetchedResponsive.id, 'banner-2');

    await cg.banner.requestResponsiveBanner('banner-2');
    expect(_stub.lastResponsiveBannerId, 'banner-2');
    await cg.banner.renderPrefetchedBanner(prefetched);
    expect(
      _stub.lastRenderedPrefetchedBanner,
      containsPair('id', 'banner-prefetch'),
    );
    cg.banner.requestOverlayBanners(
      const <OverlayBannerRequest>[
        OverlayBannerRequest(
          id: 'overlay-1',
          size: '320x50',
          anchor: OverlayPoint(x: 0.0, y: 0.0),
          position: OverlayPoint(x: 0.0, y: 0.0),
        ),
      ],
      callback: (final id, final event, final value) {
        _stub.lastOverlayCallback = <String, Object?>{
          'id': id,
          'event': event,
          'value': value,
        };
      },
    );
    expect(_stub.lastOverlayRequest, hasLength(1));
    expect(_stub.lastOverlayCallback, containsPair('id', 'overlay-1'));
    expect(cg.banner.activeBannersCount, 1);
    cg.banner.clearBanner('banner-1');
    expect(_stub.clearedBannerIds, contains('banner-1'));
    cg.banner.clearAllBanners();
    expect(_stub.clearAllBannersCalls, 1);

    expect(cg.game.link, contains('crazygames.com'));
    expect(cg.game.id, 'test-game');
    final settings = cg.game.settings;
    expect(settings.disableChat, isFalse);
    expect(settings.muteAudio, isFalse);
    expect(cg.game.isInstantJoin, isFalse);
    expect(cg.game.isInstantMultiplayer, isTrue);
    expect(cg.game.inviteParams, containsPair('roomId', 'r-1'));

    cg.game.gameplayStart();
    cg.game.gameplayStop();
    cg.game.loadingStart();
    cg.game.loadingStop();
    cg.game.happytime();
    expect(_stub.gameplayStartCalls, 1);
    expect(_stub.gameplayStopCalls, 1);
    expect(_stub.loadingStartCalls, 1);
    expect(_stub.loadingStopCalls, 1);
    expect(_stub.happytimeCalls, 1);

    final inviteLink = cg.game.inviteLink(<String, String>{'roomId': '7'});
    expect(inviteLink, contains('roomId=7'));
    final inviteButtonLink = cg.game.showInviteButton(<String, String>{
      'roomId': '8',
    });
    expect(inviteButtonLink, contains('roomId=8'));
    cg.game.hideInviteButton();
    expect(_stub.hideInviteButtonCalls, 1);
    expect(cg.game.getInviteParam('roomId'), 'r-1');

    var settingsChanged = false;
    final settingsListener = cg.game.addSettingsChangeListener((final value) {
      settingsChanged = value.disableChat;
    });
    _stub.emitSettingsChanged(<String, Object?>{
      'disableChat': true,
      'muteAudio': false,
    });
    expect(settingsChanged, isTrue);
    cg.game.removeSettingsChangeListener(settingsListener);

    var joinedRoomId = '';
    final joinRoomListener = cg.game.addJoinRoomListener((final inviteParams) {
      joinedRoomId = inviteParams['roomId'] ?? '';
    });
    _stub.emitJoinRoom(<String, String>{'roomId': 'room-77'});
    expect(joinedRoomId, 'room-77');
    cg.game.removeJoinRoomListener(joinRoomListener);

    expect(cg.user.isUserAccountAvailable, isTrue);
    expect(cg.user.systemInfo.countryCode, 'US');

    final user = await cg.user.getUser();
    expect(user?.username, 'PlayerOne.123');

    final friends = await cg.user.listFriends(page: 1, size: 10);
    expect(friends.friends, hasLength(1));
    expect(friends.friends.first.id, 'friend-1');

    expect(await cg.user.getUserToken(), 'user-token');
    expect(await cg.user.getXsollaUserToken(), 'xsolla-token');
    final promptedUser = await cg.user.showAuthPrompt();
    expect(promptedUser?.username, 'PromptedUser.55');
    final link = await cg.user.showAccountLinkPrompt();
    expect(link.answer, AccountLinkAnswer.yes);

    cg.user.addScore(100);
    cg.user.addScoreEncrypted(100, 'encrypted-100');
    cg.user.submitScore('encrypted-200');
    expect(_stub.lastScore, 100);
    expect(_stub.lastEncryptedScore, 'encrypted-100');
    expect(
      _stub.lastSubmitScorePayload,
      containsPair('encryptedScore', 'encrypted-200'),
    );

    User? authUser;
    final authListener = cg.user.addAuthListener((final user) {
      authUser = user;
    });
    _stub.emitAuthChanged(<String, Object?>{
      'username': 'AuthUser.77',
      'profilePictureUrl': 'https://example.com/avatar-auth.png',
    });
    expect(authUser?.username, 'AuthUser.77');
    cg.user.removeAuthListener(authListener);

    cg.data.setItem('gold', 42);
    expect(cg.data.getItem('gold'), '42');
    cg.data.removeItem('gold');
    expect(cg.data.getItem('gold'), isNull);
    cg.data.setItem('xp', 9);
    cg.data.clear();
    expect(cg.data.getItem('xp'), isNull);
    cg.data.syncUnityGameData();
    expect(_stub.syncUnityGameDataCalls, 1);

    cg.analytics.trackOrder(PaymentProvider.xsolla, <String, Object?>{
      'orderId': 'o-1',
      'status': 'done',
    });
    expect(_stub.lastTrackOrderProvider, 'xsolla');
    expect(_stub.lastTrackOrderPayload, containsPair('orderId', 'o-1'));
  });
}

class _SdkStubState {
  int initCalls = 0;
  String? lastAdType;
  final List<String> prefetchedAdTypes = <String>[];
  Object? _adblockPopupListener;

  Map<String, Object?>? lastBannerRequest;
  Map<String, Object?>? lastPrefetchedBannerRequest;
  Map<String, Object?>? lastPrefetchedResponsiveRequest;
  Map<String, Object?>? lastRenderedPrefetchedBanner;
  String? lastResponsiveBannerId;
  List<Map<String, Object?>>? lastOverlayRequest;
  Map<String, Object?>? lastOverlayCallback;
  final List<String> clearedBannerIds = <String>[];

  int clearAllBannersCalls = 0;
  int gameplayStartCalls = 0;
  int gameplayStopCalls = 0;
  int loadingStartCalls = 0;
  int loadingStopCalls = 0;
  int happytimeCalls = 0;
  int hideInviteButtonCalls = 0;
  int syncUnityGameDataCalls = 0;
  int? lastScore;
  String? lastEncryptedScore;
  Map<String, Object?>? lastSubmitScorePayload;
  String? lastTrackOrderProvider;
  Map<String, Object?>? lastTrackOrderPayload;

  final Map<String, Object?> _data = <String, Object?>{};

  Object? _settingsListener;
  Object? _joinRoomListener;
  Object? _authListener;

  void install() {
    final ad = js_util.jsify(<String, Object?>{
      'prefetchAd': js_util.allowInterop((final String adType) {
        prefetchedAdTypes.add(adType);
      }),
      'requestAd': js_util.allowInterop((
        final String adType,
        final Object? callbacks,
      ) {
        lastAdType = adType;
        if (callbacks != null) {
          final started = js_util.getProperty<Object?>(callbacks, 'adStarted');
          final finished = js_util.getProperty<Object?>(
            callbacks,
            'adFinished',
          );
          if (started != null) {
            js_util.callMethod<Object?>(started, 'call', const <Object?>[]);
          }
          if (finished != null) {
            js_util.callMethod<Object?>(finished, 'call', const <Object?>[]);
          }
        }
        return null;
      }),
      'hasAdblock': js_util.allowInterop(() => true),
      'addAdblockPopupListener': js_util.allowInterop((final Object listener) {
        _adblockPopupListener = listener;
      }),
      'removeAdblockPopupListener': js_util.allowInterop((
        final Object listener,
      ) {
        if (identical(_adblockPopupListener, listener)) {
          _adblockPopupListener = null;
        }
      }),
      'isAdPlaying': false,
    });

    final banner = js_util.jsify(<String, Object?>{
      'prefetchBanner': js_util.allowInterop((final Object? request) {
        final map = js_util.dartify(request) as Map<Object?, Object?>;
        lastPrefetchedBannerRequest = map.map(
          (final key, final value) => MapEntry(key.toString(), value),
        );
        return js_util.jsify(<String, Object?>{
          'id': map['id'],
          'banner': request,
          'renderOptions': js_util.jsify(<String, Object?>{'renderer': 'stub'}),
        });
      }),
      'requestBanner': js_util.allowInterop((final Object? request) {
        final map = js_util.dartify(request) as Map<Object?, Object?>;
        lastBannerRequest = map.map(
          (final key, final value) => MapEntry(key.toString(), value),
        );
        return null;
      }),
      'prefetchResponsiveBanner': js_util.allowInterop((final Object? request) {
        final map = js_util.dartify(request) as Map<Object?, Object?>;
        lastPrefetchedResponsiveRequest = map.map(
          (final key, final value) => MapEntry(key.toString(), value),
        );
        return js_util.jsify(<String, Object?>{
          'id': map['id'],
          'banner': request,
          'renderOptions': js_util.jsify(<String, Object?>{
            'renderer': 'responsive',
          }),
        });
      }),
      'requestResponsiveBanner': js_util.allowInterop((final String id) {
        lastResponsiveBannerId = id;
        return null;
      }),
      'renderPrefetchedBanner': js_util.allowInterop((final Object? request) {
        final map = js_util.dartify(request) as Map<Object?, Object?>;
        lastRenderedPrefetchedBanner = map.map(
          (final key, final value) => MapEntry(key.toString(), value),
        );
        return null;
      }),
      'clearBanner': js_util.allowInterop((final String id) {
        clearedBannerIds.add(id);
      }),
      'clearAllBanners': js_util.allowInterop(() {
        clearAllBannersCalls++;
      }),
      'requestOverlayBanners': js_util.allowInterop((
        final Object? banners,
        final Object? callback,
      ) {
        final list = js_util.dartify(banners) as List<Object?>;
        lastOverlayRequest = list
            .map(
              (final item) => (item as Map<Object?, Object?>).map(
                (final key, final value) => MapEntry(key.toString(), value),
              ),
            )
            .toList(growable: false);

        if (callback != null && lastOverlayRequest!.isNotEmpty) {
          final firstId = lastOverlayRequest!.first['id'] as String? ?? '';
          js_util.callMethod<Object?>(callback, 'call', <Object?>[
            null,
            firstId,
            'shown',
            'ok',
          ]);
        }
      }),
      'activeBannersCount': 1,
    });

    final game = js_util.jsify(<String, Object?>{
      'link': 'https://www.crazygames.com/game/test-game',
      'id': 'test-game',
      'settings': js_util.jsify(<String, Object?>{
        'disableChat': false,
        'muteAudio': false,
      }),
      'isInstantJoin': false,
      'isInstantMultiplayer': true,
      'inviteParams': js_util.jsify(<String, String>{'roomId': 'r-1'}),
      'gameplayStart': js_util.allowInterop(() {
        gameplayStartCalls++;
      }),
      'gameplayStop': js_util.allowInterop(() {
        gameplayStopCalls++;
      }),
      'loadingStart': js_util.allowInterop(() {
        loadingStartCalls++;
      }),
      'loadingStop': js_util.allowInterop(() {
        loadingStopCalls++;
      }),
      'happytime': js_util.allowInterop(() {
        happytimeCalls++;
      }),
      'inviteLink': js_util.allowInterop((final Object? params) {
        final map = js_util.dartify(params) as Map<Object?, Object?>;
        return 'https://example.com/invite?roomId=${map['roomId']}';
      }),
      'showInviteButton': js_util.allowInterop((final Object? params) {
        final map = js_util.dartify(params) as Map<Object?, Object?>;
        return 'https://example.com/button?roomId=${map['roomId']}';
      }),
      'hideInviteButton': js_util.allowInterop(() {
        hideInviteButtonCalls++;
      }),
      'getInviteParam': js_util.allowInterop((final String key) {
        if (key == 'roomId') {
          return 'r-1';
        }
        return null;
      }),
      'addSettingsChangeListener': js_util.allowInterop((
        final Object listener,
      ) {
        _settingsListener = listener;
      }),
      'removeSettingsChangeListener': js_util.allowInterop((
        final Object listener,
      ) {
        if (identical(_settingsListener, listener)) {
          _settingsListener = null;
        }
      }),
      'addJoinRoomListener': js_util.allowInterop((final Object listener) {
        _joinRoomListener = listener;
      }),
      'removeJoinRoomListener': js_util.allowInterop((final Object listener) {
        if (identical(_joinRoomListener, listener)) {
          _joinRoomListener = null;
        }
      }),
    });

    final user = js_util.jsify(<String, Object?>{
      'isUserAccountAvailable': true,
      'systemInfo': js_util.jsify(<String, Object?>{
        'countryCode': 'US',
        'locale': 'en-US',
        'device': js_util.jsify(<String, String>{'type': 'desktop'}),
        'os': js_util.jsify(<String, String>{
          'name': 'Windows',
          'version': '11',
        }),
        'browser': js_util.jsify(<String, String>{
          'name': 'Chrome',
          'version': '132.0.0.0',
        }),
        'applicationType': 'web',
      }),
      'getUser': js_util.allowInterop(
        () => js_util.jsify(<String, Object?>{
          'username': 'PlayerOne.123',
          'profilePictureUrl': 'https://example.com/avatar.png',
        }),
      ),
      'listFriends': js_util.allowInterop((final Object? options) {
        final map = js_util.dartify(options) as Map<Object?, Object?>;
        return js_util.jsify(<String, Object?>{
          'friends': <Object?>[
            js_util.jsify(<String, Object?>{
              'id': 'friend-1',
              'username': 'Friend.1',
              'profilePictureUrl': 'https://example.com/avatar-friend.png',
            }),
          ],
          'page': map['page'] ?? 1,
          'size': map['size'] ?? 10,
          'hasMore': false,
          'total': 1,
        });
      }),
      'getUserToken': js_util.allowInterop(() => 'user-token'),
      'getXsollaUserToken': js_util.allowInterop(() => 'xsolla-token'),
      'showAuthPrompt': js_util.allowInterop(
        () => js_util.jsify(<String, Object?>{
          'username': 'PromptedUser.55',
          'profilePictureUrl': 'https://example.com/avatar-prompted.png',
        }),
      ),
      'showAccountLinkPrompt': js_util.allowInterop(
        () => js_util.jsify(<String, String>{'response': 'yes'}),
      ),
      'addAuthListener': js_util.allowInterop((final Object listener) {
        _authListener = listener;
      }),
      'removeAuthListener': js_util.allowInterop((final Object listener) {
        if (identical(_authListener, listener)) {
          _authListener = null;
        }
      }),
      'addScore': js_util.allowInterop((final int score) {
        lastScore = score;
      }),
      'addScoreEncrypted': js_util.allowInterop((
        final int score,
        final String encryptedScore,
      ) {
        lastScore = score;
        lastEncryptedScore = encryptedScore;
      }),
      'submitScore': js_util.allowInterop((final Object? payload) {
        final map = js_util.dartify(payload) as Map<Object?, Object?>;
        lastSubmitScorePayload = map.map(
          (final key, final value) => MapEntry(key.toString(), value),
        );
      }),
    });

    final data = js_util.jsify(<String, Object?>{
      'clear': js_util.allowInterop(() => _data.clear()),
      'getItem': js_util.allowInterop((final String key) {
        final value = _data[key];
        return value == null ? null : '$value';
      }),
      'removeItem': js_util.allowInterop((final String key) {
        _data.remove(key);
      }),
      'setItem': js_util.allowInterop((final String key, final Object? value) {
        _data[key] = value;
      }),
      'syncUnityGameData': js_util.allowInterop(() {
        syncUnityGameDataCalls++;
      }),
    });

    final analytics = js_util.jsify(<String, Object?>{
      'trackOrder': js_util.allowInterop((
        final String provider,
        final Object? order,
      ) {
        lastTrackOrderProvider = provider;
        final map = js_util.dartify(order) as Map<Object?, Object?>;
        lastTrackOrderPayload = map.map(
          (final key, final value) => MapEntry(key.toString(), value),
        );
      }),
    });

    final sdk = js_util.jsify(<String, Object?>{
      'init': js_util.allowInterop(() {
        initCalls++;
        return null;
      }),
      'environment': 'crazygames',
      'isQaTool': false,
      'ad': ad,
      'banner': banner,
      'game': game,
      'user': user,
      'data': data,
      'analytics': analytics,
    });

    final crazyGames = js_util.jsify(<String, Object?>{'SDK': sdk});
    js_util.setProperty(js_util.globalThis, 'CrazyGames', crazyGames);
  }

  void reset() {
    initCalls = 0;
    lastAdType = null;
    prefetchedAdTypes.clear();
    _adblockPopupListener = null;
    lastBannerRequest = null;
    lastPrefetchedBannerRequest = null;
    lastPrefetchedResponsiveRequest = null;
    lastRenderedPrefetchedBanner = null;
    lastResponsiveBannerId = null;
    lastOverlayRequest = null;
    lastOverlayCallback = null;
    clearedBannerIds.clear();
    clearAllBannersCalls = 0;
    gameplayStartCalls = 0;
    gameplayStopCalls = 0;
    loadingStartCalls = 0;
    loadingStopCalls = 0;
    happytimeCalls = 0;
    hideInviteButtonCalls = 0;
    syncUnityGameDataCalls = 0;
    lastScore = null;
    lastEncryptedScore = null;
    lastSubmitScorePayload = null;
    lastTrackOrderProvider = null;
    lastTrackOrderPayload = null;
    _data.clear();
    _settingsListener = null;
    _joinRoomListener = null;
    _authListener = null;
  }

  void emitSettingsChanged(final Map<String, Object?> settings) {
    if (_settingsListener == null) {
      return;
    }
    js_util.callMethod<Object?>(_settingsListener!, 'call', <Object?>[
      null,
      js_util.jsify(settings),
    ]);
  }

  void emitJoinRoom(final Map<String, String> inviteParams) {
    if (_joinRoomListener == null) {
      return;
    }
    js_util.callMethod<Object?>(_joinRoomListener!, 'call', <Object?>[
      null,
      js_util.jsify(inviteParams),
    ]);
  }

  void emitAuthChanged(final Map<String, Object?> user) {
    if (_authListener == null) {
      return;
    }
    js_util.callMethod<Object?>(_authListener!, 'call', <Object?>[
      null,
      js_util.jsify(user),
    ]);
  }

  void emitAdblockPopup(final String state) {
    if (_adblockPopupListener == null) {
      return;
    }
    js_util.callMethod<Object?>(_adblockPopupListener!, 'call', <Object?>[
      null,
      state,
    ]);
  }
}
