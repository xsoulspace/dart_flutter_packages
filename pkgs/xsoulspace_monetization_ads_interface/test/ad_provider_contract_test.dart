import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';

void main() {
  test('AdProvider implementations can provide lifecycle operations', () async {
    final provider = _TestAdProvider();

    await provider.init();
    await provider.showRewardedAd(adUnitId: 'rewarded');
    await provider.showInterstitialAd(adUnitId: 'interstitial');
    final banner = provider.buildBannerAd(
      adUnitId: 'banner',
      adSize: const Size(728, 90),
    );

    expect(provider.events, <String>['init', 'rewarded', 'interstitial']);
    expect(banner, isA<SizedBox>());
  });
}

final class _TestAdProvider implements AdProvider {
  final List<String> events = <String>[];

  @override
  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) => const SizedBox(width: 728, height: 90);

  @override
  Future<void> init() async => events.add('init');

  @override
  Future<void> showInterstitialAd({required final String adUnitId}) async {
    events.add('interstitial');
  }

  @override
  Future<void> showRewardedAd({required final String adUnitId}) async {
    events.add('rewarded');
  }
}
