import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';

/// A no-op implementation of [AdProvider] that does nothing.
/// Useful for development, testing, or for monetization models
/// that do not include ads.
class NoopAdProvider implements AdProvider {
  @override
  Future<void> init() async {}

  @override
  Future<void> showRewardedAd({required final String adUnitId}) async {}

  @override
  Future<void> showInterstitialAd({required final String adUnitId}) async {}

  @override
  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) => const SizedBox.shrink();
}
