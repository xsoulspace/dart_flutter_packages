import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_ads_foundation/xsoulspace_monetization_ads_foundation.dart';

void main() {
  test('re-exports AdProvider contract for foundation packages', () async {
    final provider = _FakeAdProvider();

    await provider.init();
    await provider.showRewardedAd(adUnitId: 'rewarded');
    await provider.showInterstitialAd(adUnitId: 'interstitial');

    expect(provider.initCalls, 1);
    expect(provider.rewardedCalls, 1);
    expect(provider.interstitialCalls, 1);
    expect(
      provider.buildBannerAd(adUnitId: 'banner', adSize: const Size(320, 50)),
      isA<SizedBox>(),
    );
  });
}

final class _FakeAdProvider implements AdProvider {
  int initCalls = 0;
  int rewardedCalls = 0;
  int interstitialCalls = 0;

  @override
  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) {
    return const SizedBox(width: 320, height: 50);
  }

  @override
  Future<void> init() async {
    initCalls += 1;
  }

  @override
  Future<void> showInterstitialAd({required final String adUnitId}) async {
    interstitialCalls += 1;
  }

  @override
  Future<void> showRewardedAd({required final String adUnitId}) async {
    rewardedCalls += 1;
  }
}
