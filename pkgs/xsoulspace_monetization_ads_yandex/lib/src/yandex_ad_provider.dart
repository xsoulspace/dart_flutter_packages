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
    await YandexAds.initialize();
    if (debug) {
      await YandexAds.setLogging(true);
      await YandexAds.showDebugPanel();
    }
    await YandexAds.setAgeRestricted(true);
  }

  @override
  Future<void> showRewardedAd({required final String adUnitId}) async {
    final completer = Completer<RewardedAd>();
    final loader = RewardedAdLoader();
    //TODO(arenukvern): fix implementation
    // final adLoader = await RewardedAdLoader.create(
    //   onAdFailedToLoad: completer.completeError,
    //   onAdLoaded: completer.complete,
    // );
    await loader.loadAd(
      adRequest: AdRequest(adUnitId: adUnitId),
      // adRequestConfiguration: AdRequestConfiguration(adUnitId: adUnitId),
    );
    final ad = await completer.future;
    await ad.setAdEventListener(
      eventListener: RewardedAdEventListener(
        onAdFailedToShow: (final error) => debugPrint(error.toString()),
        onAdShown: () => debugPrint('ad shown'),
        onAdDismissed: () => debugPrint('ad dismissed'),
        onAdClicked: () => debugPrint('ad clicked'),
        onAdImpression: (final data) => debugPrint(data.toString()),
        onRewarded: (final reward) => debugPrint(reward.toString()),
      ),
    );
    await ad.show();
  }

  @override
  Future<void> showInterstitialAd({required final String adUnitId}) async {
    final completer = Completer<InterstitialAd>();
    final loader = InterstitialAdLoader();
    //TODO(arenukvern): fix implementation
    // final adLoader = await InterstitialAdLoader.create(
    //   onAdLoaded: completer.complete,
    //   onAdFailedToLoad: completer.completeError,
    // );
    await loader.loadAd(
      adRequest: AdRequest(adUnitId: adUnitId),
      // adRequestConfiguration: AdRequestConfiguration(adUnitId: adUnitId),
    );
    final ad = await completer.future;
    await ad.setAdEventListener(
      eventListener: InterstitialAdEventListener(
        onAdFailedToShow: (final error) => debugPrint(error.toString()),
        onAdShown: () => debugPrint('ad shown'),
        onAdDismissed: () => debugPrint('ad dismissed'),
        onAdClicked: () => debugPrint('ad clicked'),
        onAdImpression: (final data) => debugPrint(data.toString()),
      ),
    );
    await ad.show();
  }

  @override
  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) {
    if (adSize is! BannerAdSize) {
      throw ArgumentError(
        'adSize must be of type BannerAdSize for YandexAdProvider',
      );
    }
    throw UnimplementedError();
    // return BannerAd(adUnitId: adUnitId, adSize: adSize);
  }
}
