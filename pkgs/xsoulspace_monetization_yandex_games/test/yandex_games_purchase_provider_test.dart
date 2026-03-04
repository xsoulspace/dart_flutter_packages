import 'package:test/test.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_monetization_yandex_games/xsoulspace_monetization_yandex_games.dart';

void main() {
  group('YandexGamesPurchaseProvider', () {
    test('maps init failures to notAvailable status', () async {
      final provider = YandexGamesPurchaseProvider(
        initClient:
            ({
              final bool signed = false,
              final String expectedGlobal = 'YaGames',
            }) async {
          throw StateError('sdk unavailable');
        },
      );

      final status = await provider.init();
      expect(status, MonetizationStoreStatus.notAvailable);
    });

    test('returns explicit failure for unsupported cancel flow', () async {
      final provider = YandexGamesPurchaseProvider(
        initClient:
            ({
              final bool signed = false,
              final String expectedGlobal = 'YaGames',
            }) async {
          throw StateError('sdk unavailable');
        },
      );

      final result = await provider.cancel('purchase-id');

      expect(result.isFailure, isTrue);
      expect(result.error, contains('not supported'));
    });
  });
}
