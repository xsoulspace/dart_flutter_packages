import 'package:flutter/widgets.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';

/// Ad provider that performs no operations.
class NoopAdProvider implements AdProvider {
  @override
  Future<void> init() async {}

  @override
  Future<void> showRewardedAd({required String adUnitId}) async {}

  @override
  Future<void> showInterstitialAd({required String adUnitId}) async {}

  @override
  Widget buildBannerAd({
    required String adUnitId,
    required Object adSize,
  }) {
    return const SizedBox.shrink();
  }
}
