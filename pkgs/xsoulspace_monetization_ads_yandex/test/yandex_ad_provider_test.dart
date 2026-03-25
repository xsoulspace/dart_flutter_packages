import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_ads_yandex/xsoulspace_monetization_ads_yandex.dart';

void main() {
  group('YandexAdProvider', () {
    test('stores debug mode configuration', () {
      final provider = YandexAdProvider(debug: true);

      expect(provider.debug, isTrue);
    });

    test('rejects non-BannerAdSize adSize payloads', () {
      final provider = YandexAdProvider();

      expect(
        () => provider.buildBannerAd(adUnitId: 'banner', adSize: Object()),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
