import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';

/// {@template ad_manager}
/// Manages advertisements by delegating to a specific [AdProvider].
/// {@endtemplate}
class AdManager {
  AdManager(this.provider);
  final AdProvider provider;

  Future<void> init() => provider.init();

  Future<void> showRewardedAd({required final String adUnitId}) =>
      provider.showRewardedAd(adUnitId: adUnitId);

  Future<void> showInterstitialAd({required final String adUnitId}) =>
      provider.showInterstitialAd(adUnitId: adUnitId);

  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) => provider.buildBannerAd(adUnitId: adUnitId, adSize: adSize);
}
