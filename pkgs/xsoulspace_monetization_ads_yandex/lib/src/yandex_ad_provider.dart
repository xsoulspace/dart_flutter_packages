import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';
import 'package:yandex_mobileads/mobile_ads.dart';

/// {@template yandex_ad_provider}
/// Implementation of [AdProvider] using Yandex Mobile Ads.
/// {@endtemplate}
class YandexAdProvider implements AdProvider {
  YandexAdProvider({this.debug = false});
  final bool debug;

  @override
  Future<void> init() async {
    await MobileAds.initialize();
    if (debug) {
      await MobileAds.setLogging(true);
      await MobileAds.showDebugPanel();
    }
    await MobileAds.setAgeRestrictedUser(true);
  }

  @override
  Future<void> showRewardedAd({required String adUnitId}) async {
    final completer = Completer<RewardedAd>();
    final adLoader = await RewardedAdLoader.create(
      onAdFailedToLoad: (error) => completer.completeError(error),
      onAdLoaded: (ad) => completer.complete(ad),
    );
    await adLoader.loadAd(
      adRequestConfiguration: AdRequestConfiguration(adUnitId: adUnitId),
    );
    final ad = await completer.future;
    await ad.setAdEventListener(
      onAdFailedToShow: (error) => debugPrint(error.toString()),
      onAdShown: () => debugPrint('ad shown'),
      onAdDismissed: () => debugPrint('ad dismissed'),
      onAdClicked: () => debugPrint('ad clicked'),
      onImpression: (data) => debugPrint(data.toString()),
      onAdRewarded: (reward) => debugPrint(reward.toString()),
    );
    await ad.show();
  }

  @override
  Future<void> showInterstitialAd({required String adUnitId}) async {
    final adLoader = InterstitialAdLoader();
    await adLoader.load(adUnitId: adUnitId);

    final ad = await adLoader.waitForAd();
    ad.setAdEventListener(
      onAdFailedToShow: (error) => debugPrint(error.toString()),
      onAdShown: () => debugPrint('ad shown'),
      onAdDismissed: () => debugPrint('ad dismissed'),
      onAdClicked: () => debugPrint('ad clicked'),
      onImpression: (data) => debugPrint(data.toString()),
    );
    await ad.show();
  }

  @override
  Widget buildBannerAd({required String adUnitId, required Object adSize}) {
    if (adSize is! BannerAdSize) {
      throw ArgumentError(
        'adSize must be of type BannerAdSize for YandexAdProvider',
      );
    }
    return BannerAd(adUnitId: adUnitId, adSize: adSize);
  }
}
