import 'package:flutter_test/flutter_test.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';

void main() {
  group('RustoreBillingClient', () {
    late RustoreBillingClient client;

    setUp(() {
      client = RustoreBillingClient.instance;
    });

    test('is singleton', () {
      expect(client, same(RustoreBillingClient.instance));
    });

    test(
      'getProducts throws RustoreBillingException on placeholder platform',
      () {
        expect(
          () => client.getProducts(<String>['test_product']),
          throwsA(isA<RustoreBillingException>()),
        );
      },
    );
  });

  group('RustoreBillingConfig', () {
    test('defaults are applied', () {
      final config = RustoreBillingConfig(
        consoleApplicationId: 'app',
        deeplinkScheme: 'scheme',
      );

      expect(config.debugLogs, false);
      expect(config.defaultTheme, RustoreBillingTheme.system);
      expect(config.enableLogging, false);
    });
  });

  group('Enums', () {
    test('purchase status includes unknown fallback', () {
      expect(
        RustorePurchaseStatus.values.contains(RustorePurchaseStatus.unknown),
        isTrue,
      );
    });

    test('product type includes unknown fallback', () {
      expect(
        RustoreProductType.values.contains(RustoreProductType.unknown),
        isTrue,
      );
    });
  });
}
