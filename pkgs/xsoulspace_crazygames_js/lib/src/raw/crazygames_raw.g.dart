// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: CrazyGames SDK v3.6.0
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('CrazyGames')
external CrazyGamesGlobalRaw get crazyGames;
@JS('CrazyGames.SDK')
external CrazyGamesSdkRaw get crazyGamesSdk;

typedef EnvironmentRaw = JSString;

abstract final class EnvironmentRawValues {
  static JSString get crazygames => 'crazygames'.toJS;
  static JSString get local => 'local'.toJS;
  static JSString get disabled => 'disabled'.toJS;
}

typedef AdTypeRaw = JSString;

abstract final class AdTypeRawValues {
  static JSString get midgame => 'midgame'.toJS;
  static JSString get rewarded => 'rewarded'.toJS;
}

typedef PaymentProviderRaw = JSString;
typedef AdblockPopupStateRaw = JSString;
typedef DeviceTypeRaw = JSString;

abstract final class DeviceTypeRawValues {
  static JSString get desktop => 'desktop'.toJS;
  static JSString get tablet => 'tablet'.toJS;
  static JSString get mobile => 'mobile'.toJS;
}

typedef ApplicationTypeRaw = JSString;

abstract final class ApplicationTypeRawValues {
  static JSString get googlePlayStore => 'google_play_store'.toJS;
  static JSString get appleStore => 'apple_store'.toJS;
  static JSString get pwa => 'pwa'.toJS;
  static JSString get web => 'web'.toJS;
}

extension type SdkErrorRaw(JSObject _) implements JSObject {
  external JSString get code;
  external JSString get message;
  external JSString? get containerId;
}

extension type UserRaw(JSObject _) implements JSObject {
  external JSString? get id;
  external JSString get username;
  external JSString get profilePictureUrl;
}

extension type BrowserInfoRaw(JSObject _) implements JSObject {
  external JSString get name;
  external JSString get version;
}

extension type OsInfoRaw(JSObject _) implements JSObject {
  external JSString get name;
  external JSString get version;
}

extension type DeviceInfoRaw(JSObject _) implements JSObject {
  external DeviceTypeRaw get type;
}

extension type SystemInfoRaw(JSObject _) implements JSObject {
  external JSString get countryCode;
  external JSString get locale;
  external DeviceInfoRaw get device;
  external OsInfoRaw get os;
  external BrowserInfoRaw get browser;
  external ApplicationTypeRaw get applicationType;
}

extension type FriendRaw(JSObject _) implements JSObject {
  external JSString get id;
  external JSString get username;
  external JSString get profilePictureUrl;
}

extension type FriendsPageRaw(JSObject _) implements JSObject {
  external JSArray<FriendRaw> get friends;
  external JSNumber get page;
  external JSNumber get size;
  external JSBoolean get hasMore;
  external JSNumber get total;
}

extension type FriendsListOptionsRaw(JSObject _) implements JSObject {
  external JSNumber get page;
  external JSNumber get size;
}

extension type AccountLinkResponseRaw(JSObject _) implements JSObject {
  external JSString get response;
}

extension type GameSettingsRaw(JSObject _) implements JSObject {
  external JSBoolean get disableChat;
  external JSBoolean get muteAudio;
}

extension type BannerRequestRaw(JSObject _) implements JSObject {
  external JSString get id;
  external JSNumber get width;
  external JSNumber get height;
  external JSNumber? get x;
  external JSNumber? get y;
}

extension type OverlayBannerRequestRaw(JSObject _) implements JSObject {
  external JSString get id;
  external JSString get size;
  external JSAny? get anchor;
  external JSAny? get position;
  external JSAny? get pivot;
}

extension type CrazyGamesAdCallbacksRaw(JSObject _) implements JSObject {
  external JSAny? get adStarted;
  external JSAny? get adFinished;
  external JSAny? get adError;
}

extension type CrazyGamesAdRaw(JSObject _) implements JSObject {
  external void prefetchAd(AdTypeRaw adType);
  external JSPromise<JSAny?> requestAd(
    AdTypeRaw adType, [
    CrazyGamesAdCallbacksRaw? callbacks,
  ]);
  external JSPromise<JSBoolean> hasAdblock();
  external void addAdblockPopupListener(JSAny? listener);
  external void removeAdblockPopupListener(JSAny? listener);
  external JSBoolean get isAdPlaying;
}

extension type CrazyGamesBannerRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> prefetchBanner(BannerRequestRaw request);
  external JSPromise<JSAny?> requestBanner(BannerRequestRaw request);
  external JSPromise<JSAny?> prefetchResponsiveBanner(JSAny? request);
  external JSPromise<JSAny?> requestResponsiveBanner(JSString id);
  external JSPromise<JSAny?> renderPrefetchedBanner(JSAny? request);
  external void clearBanner(JSString id);
  external void clearAllBanners();
  external void requestOverlayBanners(
    JSArray<OverlayBannerRequestRaw> banners, [
    JSAny? callback,
  ]);
  external JSNumber get activeBannersCount;
}

extension type CrazyGamesGameRaw(JSObject _) implements JSObject {
  external JSString get link;
  external JSString get id;
  external GameSettingsRaw get settings;
  external JSBoolean get isInstantJoin;
  external JSBoolean get isInstantMultiplayer;
  external JSAny? get inviteParams;
  external void happytime();
  external void gameplayStart();
  external void gameplayStop();
  external void loadingStart();
  external void loadingStop();
  external JSString inviteLink(JSObject params);
  external JSString showInviteButton(JSObject params);
  external void hideInviteButton();
  external JSAny? getInviteParam(JSString key);
  external void addSettingsChangeListener(JSAny? listener);
  external void removeSettingsChangeListener(JSAny? listener);
  external void addJoinRoomListener(JSAny? listener);
  external void removeJoinRoomListener(JSAny? listener);
  external JSAny? updateRoom(JSArray<JSAny?> args);
  external JSAny? leftRoom(JSArray<JSAny?> args);
}

extension type CrazyGamesGameV2Raw(JSObject _) implements JSObject {
  external void updateRoom(JSAny? options);
  external void leftRoom();
}

extension type CrazyGamesUserRaw(JSObject _) implements JSObject {
  external JSBoolean get isUserAccountAvailable;
  external SystemInfoRaw get systemInfo;
  external JSPromise<JSAny?> showAuthPrompt();
  external JSPromise<AccountLinkResponseRaw> showAccountLinkPrompt();
  external JSPromise<JSAny?> getUser();
  external void addAuthListener(JSAny? listener);
  external void removeAuthListener(JSAny? listener);
  external JSPromise<JSString> getUserToken();
  external JSPromise<JSString> getXsollaUserToken();
  external JSPromise<FriendsPageRaw> listFriends(FriendsListOptionsRaw options);
  external void addScore(JSNumber score);
  external void addScoreEncrypted(JSNumber score, JSString encryptedScore);
  external void submitScore(JSAny? payload);
}

extension type CrazyGamesDataRaw(JSObject _) implements JSObject {
  external void clear();
  external JSAny? getItem(JSString key);
  external void removeItem(JSString key);
  external void setItem(JSString key, JSAny? value);
  external void syncUnityGameData();
}

extension type CrazyGamesAnalyticsRaw(JSObject _) implements JSObject {
  external void trackOrder(PaymentProviderRaw provider, JSObject order);
}

extension type CrazyGamesSdkRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> init();
  external CrazyGamesAdRaw get ad;
  external CrazyGamesBannerRaw get banner;
  external CrazyGamesGameRaw get game;
  @JS('game-v2')
  external CrazyGamesGameV2Raw? get game_v2;
  external CrazyGamesUserRaw get user;
  external CrazyGamesDataRaw get data;
  external CrazyGamesAnalyticsRaw get analytics;
  external EnvironmentRaw get environment;
  external JSBoolean get isQaTool;
}

extension type CrazyGamesGlobalRaw(JSObject _) implements JSObject {
  external CrazyGamesSdkRaw get SDK;
}
