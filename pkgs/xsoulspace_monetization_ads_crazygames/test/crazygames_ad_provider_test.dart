import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_crazygames_js/xsoulspace_crazygames_js.dart';
import 'package:xsoulspace_monetization_ads_crazygames/xsoulspace_monetization_ads_crazygames.dart';

void main() {
  group('CrazyGamesAdProvider', () {
    test('returns a banner widget for unknown adSize values', () {
      final provider = CrazyGamesAdProvider(
        initClient: () async => CrazyGamesClient(),
      );

      final banner = provider.buildBannerAd(
        adUnitId: 'banner_1',
        adSize: Object(),
      );

      expect(banner, isA<Widget>());
    });

    test('surfaces unsupported SDK calls on non-web', () async {
      final provider = CrazyGamesAdProvider(
        initClient: () async => CrazyGamesClient(),
      );

      await expectLater(
        provider.showRewardedAd(adUnitId: 'rewarded_1'),
        throwsA(isA<UnsupportedError>()),
      );

      await expectLater(
        provider.showInterstitialAd(adUnitId: 'interstitial_1'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
