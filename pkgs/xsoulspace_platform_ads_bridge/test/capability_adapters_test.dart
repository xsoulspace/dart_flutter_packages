import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';
import 'package:xsoulspace_platform_ads_bridge/xsoulspace_platform_ads_bridge.dart';

void main() {
  test('ads capability forwards provider instance', () {
    final provider = _FakeAdProvider();
    final capability = AdsCapabilityAdapter(provider);

    expect(capability.adProvider, same(provider));
    expect(capability.capabilityName, 'monetization.ads');
  });

  test('noop ads capability exposes default no-op provider', () {
    final ads = NoopAdsCapability();

    expect(ads.adProvider, isA<NoopAdProvider>());
  });
}

final class _FakeAdProvider implements AdProvider {
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
  }) {
    return const SizedBox.shrink();
  }
}
