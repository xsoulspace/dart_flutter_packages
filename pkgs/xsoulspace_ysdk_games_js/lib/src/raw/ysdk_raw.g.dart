// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: @types/ysdk@1.2.0
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('YaGames')
external YaGamesGlobalRaw get yaGames;

extension type YaGamesGlobalRaw(JSObject _) implements JSObject {
  external JSPromise<SDKRaw> init([JSAny? opts]);
}

extension type SDKRaw(JSObject _) implements JSObject {
  external JSAny? get EVENTS;
  external JSAny? get adv;
  external JSAny? get auth;
  external JSAny? get clipboard;
  external DeviceInfoRaw get deviceInfo;
  external EnvironmentRaw get environment;
  external JSAny? get features;
  external JSAny? get feedback;
  external YLeaderboardsRaw get leaderboards;
  external MultiplayerRaw get multiplayer;
  external PaymentsRaw get payments;
  external JSAny? get screen;
  external JSAny? get shortcut;
  external JSPromise<JSAny?> dispatchEvent(
    SdkEventNameRaw eventName, [
    JSAny? detail,
  ]);
  external JSPromise<JSObject> getFlags([GetFlagsParamsRaw? params]);
  external JSPromise<LeaderboardsRaw> getLeaderboards();
  external JSPromise<PaymentsRaw> getPayments([JSAny? opts]);
  external JSPromise<JSAny?> getPlayer([JSAny? opts]);
  external JSPromise<SafeStorageRaw> getStorage();
  external JSPromise<JSBoolean> isAvailableMethod(JSString methodName);
  external void off(JSString event, JSAny? observer);
  @JS('on')
  external JSAny? onValue(JSString event, JSAny? observer);
  external JSAny? onEvent(SdkEventNameRaw eventName, JSAny? listener);
  external JSNumber serverTime();
}

extension type ClientFeatureRaw(JSObject _) implements JSObject {
  external JSString get name;
  external JSString get value;
}

extension type GetFlagsParamsRaw(JSObject _) implements JSObject {
  external JSArray<ClientFeatureRaw>? get clientFeatures;
  external JSObject? get defaultFlags;
}

extension type GameRaw(JSObject _) implements JSObject {
  external JSString get appID;
  external JSString get coverURL;
  external JSString get iconURL;
  external JSString get title;
  external JSString get url;
}

extension type SignatureRaw(JSObject _) implements JSObject {
  external JSString get signature;
}

extension type EnvironmentRaw(JSObject _) implements JSObject {
  external JSAny? get app;
  external JSAny? get browser;
  external JSAny? get i18n;
  external JSAny? get payload;
}

typedef DeviceTypeRaw = JSString;

abstract final class DeviceTypeRawValues {
  static JSString get desktop => 'desktop'.toJS;
  static JSString get mobile => 'mobile'.toJS;
  static JSString get tablet => 'tablet'.toJS;
  static JSString get tv => 'tv'.toJS;
}

extension type DeviceInfoRaw(JSObject _) implements JSObject {
  external JSBoolean isDesktop();
  external JSBoolean isMobile();
  external JSBoolean isTV();
  external JSBoolean isTablet();
  external DeviceTypeRaw get type;
}

typedef SafeStorageRaw = JSObject;
extension type PlayerRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> getData([JSAny? keys]);
  external JSPromise<JSArray<JSAny?>> getIDsPerGame();
  external JSString getMode();
  external JSString getName();
  external JSString getPayingStatus();
  external JSString getPhoto(JSString size);
  external JSPromise<JSAny?> getStats([JSAny? keys]);
  external JSString getUniqueID();
  external JSPromise<IncrementedStatsRaw> incrementStats(JSAny? stats);
  external JSBoolean isAuthorized();
  external JSPromise<JSAny?> setData(JSAny? data, [JSBoolean? flush]);
  external JSPromise<JSAny?> setStats(JSObject stats);
}

extension type IncrementedStatsRaw(JSObject _) implements JSObject {
  external JSArray<JSString> get newKeys;
  external JSAny? get stats;
}

extension type PurchaseRaw(JSObject _) implements JSObject {
  external JSString? get developerPayload;
  external JSString get productID;
  external JSString get purchaseToken;
}

extension type ProductRaw(JSObject _) implements JSObject {
  external JSString get description;
  external JSString get id;
  external JSString get imageURI;
  external JSString get price;
  external JSString get priceCurrencyCode;
  external JSString get priceValue;
  external JSString get title;
  external JSString getPriceCurrencyImage(JSString size);
}

extension type PaymentsRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> consumePurchase(JSString token);
  external JSPromise<JSArray<ProductRaw>> getCatalog();
  external JSPromise<JSAny?> getPurchases();
  external JSPromise<JSAny?> purchase([JSAny? opts]);
}

extension type GetLeaderboardEntriesOptsRaw(JSObject _) implements JSObject {
  external JSBoolean? get includeUser;
  external JSNumber? get quantityAround;
  external JSNumber? get quantityTop;
}

extension type LeaderboardsRaw(JSObject _) implements JSObject {
  external JSPromise<LeaderboardDescriptionRaw> getLeaderboardDescription(
    JSString leaderboardName,
  );
  external JSPromise<LeaderboardEntriesDataRaw> getLeaderboardEntries(
    JSString leaderboardName, [
    GetLeaderboardEntriesOptsRaw? opts,
  ]);
  external JSPromise<LeaderboardEntryRaw> getLeaderboardPlayerEntry(
    JSString leaderboardName,
  );
  external JSPromise<JSAny?> setLeaderboardScore(
    JSString leaderboardName,
    JSNumber score, [
    JSString? extraData,
  ]);
}

extension type YLeaderboardsRaw(JSObject _) implements JSObject {
  external JSPromise<LeaderboardDescriptionRaw> getDescription(
    JSString leaderboardName,
  );
  external JSPromise<LeaderboardEntriesDataRaw> getEntries(
    JSString leaderboardName, [
    GetLeaderboardEntriesOptsRaw? opts,
  ]);
  external JSPromise<LeaderboardEntryRaw> getPlayerEntry(
    JSString leaderboardName,
  );
  external JSPromise<JSAny?> setScore(
    JSString leaderboardName,
    JSNumber score, [
    JSString? extraData,
  ]);
}

extension type LeaderboardEntriesDataRaw(JSObject _) implements JSObject {
  external JSArray<LeaderboardEntryRaw> get entries;
  external LeaderboardDescriptionRaw get leaderboard;
  external JSArray<JSAny?> get ranges;
  external JSNumber get userRank;
}

extension type LeaderboardEntryRaw(JSObject _) implements JSObject {
  external JSString? get extraData;
  external JSString get formattedScore;
  external JSAny? get player;
  external JSNumber get rank;
  external JSNumber get score;
}

extension type LeaderboardDescriptionRaw(JSObject _) implements JSObject {
  external JSString get appID;
  @JS('default')
  external JSBoolean get defaultValue;
  external JSAny? get description;
  external JSString get name;
  external JSObject get title;
}

typedef FeedbackErrorRaw = JSString;

abstract final class FeedbackErrorRawValues {
  static JSString get gameRated => 'GAME_RATED'.toJS;
  static JSString get noAuth => 'NO_AUTH'.toJS;
  static JSString get reviewAlreadyRequested => 'REVIEW_ALREADY_REQUESTED'.toJS;
  static JSString get unknown => 'UNKNOWN'.toJS;
}

typedef StickyAdvErrorRaw = JSString;

abstract final class StickyAdvErrorRawValues {
  static JSString get advIsNotConnected => 'ADV_IS_NOT_CONNECTED'.toJS;
  static JSString get unknown => 'UNKNOWN'.toJS;
}

typedef SdkEventNameRaw = JSString;

abstract final class SdkEventNameRawValues {
  static JSString get exit => 'EXIT'.toJS;
  static JSString get historyBack => 'HISTORY_BACK'.toJS;
}

typedef ISO_639_1Raw = JSString;

abstract final class ISO_639_1RawValues {
  static JSString get af => 'af'.toJS;
  static JSString get am => 'am'.toJS;
  static JSString get ar => 'ar'.toJS;
  static JSString get az => 'az'.toJS;
  static JSString get be => 'be'.toJS;
  static JSString get bg => 'bg'.toJS;
  static JSString get bn => 'bn'.toJS;
  static JSString get ca => 'ca'.toJS;
  static JSString get cs => 'cs'.toJS;
  static JSString get da => 'da'.toJS;
  static JSString get de => 'de'.toJS;
  static JSString get el => 'el'.toJS;
  static JSString get en => 'en'.toJS;
  static JSString get es => 'es'.toJS;
  static JSString get et => 'et'.toJS;
  static JSString get eu => 'eu'.toJS;
  static JSString get fa => 'fa'.toJS;
  static JSString get fi => 'fi'.toJS;
  static JSString get fr => 'fr'.toJS;
  static JSString get gl => 'gl'.toJS;
  static JSString get he => 'he'.toJS;
  static JSString get hi => 'hi'.toJS;
  static JSString get hr => 'hr'.toJS;
  static JSString get hu => 'hu'.toJS;
  static JSString get hy => 'hy'.toJS;
  static JSString get id => 'id'.toJS;
  static JSString get isValue => 'is'.toJS;
  static JSString get it => 'it'.toJS;
  static JSString get ja => 'ja'.toJS;
  static JSString get ka => 'ka'.toJS;
  static JSString get kk => 'kk'.toJS;
  static JSString get km => 'km'.toJS;
  static JSString get kn => 'kn'.toJS;
  static JSString get ko => 'ko'.toJS;
  static JSString get ky => 'ky'.toJS;
  static JSString get lo => 'lo'.toJS;
  static JSString get lt => 'lt'.toJS;
  static JSString get lv => 'lv'.toJS;
  static JSString get mk => 'mk'.toJS;
  static JSString get ml => 'ml'.toJS;
  static JSString get mn => 'mn'.toJS;
  static JSString get mr => 'mr'.toJS;
  static JSString get ms => 'ms'.toJS;
  static JSString get my => 'my'.toJS;
  static JSString get ne => 'ne'.toJS;
  static JSString get nl => 'nl'.toJS;
  static JSString get no => 'no'.toJS;
  static JSString get pl => 'pl'.toJS;
  static JSString get pt => 'pt'.toJS;
  static JSString get ro => 'ro'.toJS;
  static JSString get ru => 'ru'.toJS;
  static JSString get si => 'si'.toJS;
  static JSString get sk => 'sk'.toJS;
  static JSString get sl => 'sl'.toJS;
  static JSString get sr => 'sr'.toJS;
  static JSString get sv => 'sv'.toJS;
  static JSString get sw => 'sw'.toJS;
  static JSString get ta => 'ta'.toJS;
  static JSString get te => 'te'.toJS;
  static JSString get tg => 'tg'.toJS;
  static JSString get th => 'th'.toJS;
  static JSString get tk => 'tk'.toJS;
  static JSString get tl => 'tl'.toJS;
  static JSString get tr => 'tr'.toJS;
  static JSString get uk => 'uk'.toJS;
  static JSString get ur => 'ur'.toJS;
  static JSString get uz => 'uz'.toJS;
  static JSString get vi => 'vi'.toJS;
  static JSString get zh => 'zh'.toJS;
  static JSString get zu => 'zu'.toJS;
}

typedef TopLevelDomainRaw = JSString;

abstract final class TopLevelDomainRawValues {
  static JSString get az => 'az'.toJS;
  static JSString get by => 'by'.toJS;
  static JSString get coIl => 'co.il'.toJS;
  static JSString get com => 'com'.toJS;
  static JSString get comAm => 'com.am'.toJS;
  static JSString get comGe => 'com.ge'.toJS;
  static JSString get comTr => 'com.tr'.toJS;
  static JSString get ee => 'ee'.toJS;
  static JSString get fr => 'fr'.toJS;
  static JSString get kg => 'kg'.toJS;
  static JSString get kz => 'kz'.toJS;
  static JSString get lt => 'lt'.toJS;
  static JSString get lv => 'lv'.toJS;
  static JSString get md => 'md'.toJS;
  static JSString get ru => 'ru'.toJS;
  static JSString get tj => 'tj'.toJS;
  static JSString get tm => 'tm'.toJS;
  static JSString get ua => 'ua'.toJS;
  static JSString get uz => 'uz'.toJS;
}

typedef SerializableRaw = JSAny?;
extension type MultiplayerRaw(JSObject _) implements JSObject {
  external MultiplayerSessionsRaw get sessions;
}

extension type MultiplayerSessionsRaw(JSObject _) implements JSObject {
  external void commit(MultiplayerSessionsCommitPayloadRaw payload);
  external JSPromise<JSArray<MultiplayerSessionsOpponentRaw>> init([
    MultiplayerSessionsInitOptionsRaw? options,
  ]);
  external JSPromise<CallbackBaseMessageDataRaw> push(
    MultiplayerSessionsMetaRaw meta,
  );
}

extension type CallbackBaseMessageDataRaw(JSObject _) implements JSObject {
  external JSAny? get data;
  external JSAny? get error;
  external JSString get status;
}

extension type MultiplayerSessionsCommitPayloadRaw(JSObject _)
    implements JSObject {
  external JSObject get data;
  external JSNumber get time;
}

extension type MultiplayerSessionsInitOptionsRaw(JSObject _)
    implements JSObject {
  external JSNumber? get count;
  external JSBoolean? get isEventBased;
  external JSNumber? get maxOpponentTurnTime;
  external MultiplayerSessionsMetaRangesRaw? get meta;
}

extension type MultiplayerSessionsMetaRaw(JSObject _) implements JSObject {
  external JSNumber get meta1;
  external JSNumber get meta2;
  external JSNumber get meta3;
}

extension type MultiplayerSessionsMetaRangesRaw(JSObject _)
    implements JSObject {
  external JSAny? get meta1;
  external JSAny? get meta2;
  external JSAny? get meta3;
}

extension type MultiplayerSessionsOpponentRaw(JSObject _) implements JSObject {
  external JSString get id;
  external MultiplayerSessionsMetaRaw get meta;
  external JSArray<MultiplayerSessionsCommitPayloadRaw> get transactions;
}
