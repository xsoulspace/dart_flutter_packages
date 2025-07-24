import 'package:flutter_test/flutter_test.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';

void main() {
  group('RustoreBillingClient', () {
    late RustoreBillingClient client;

    setUp(() {
      client = RustoreBillingClient.instance;
    });

    test('should be a singleton', () {
      final client1 = RustoreBillingClient.instance;
      final client2 = RustoreBillingClient.instance;
      expect(client1, equals(client2));
    });

    test('should throw exception when platform not implemented', () {
      expect(
        () => client.getProducts(['test']),
        throwsA(isA<RustoreBillingException>()),
      );
    });

    test(
      'should throw exception when calling onNewIntent without platform',
      () {
        expect(
          () => client.onNewIntent('test'),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );

    group('RustoreBillingConfig', () {
      test('should create config with required parameters', () {
        final config = RustoreBillingConfig(
          consoleApplicationId: 'test_app_id',
          deeplinkScheme: 'test_scheme',
        );

        expect(config.consoleApplicationId, equals('test_app_id'));
        expect(config.deeplinkScheme, equals('test_scheme'));
        expect(config.debugLogs, equals(false));
      });

      test('should create config with debug logs enabled', () {
        final config = RustoreBillingConfig(
          consoleApplicationId: 'test_app_id',
          deeplinkScheme: 'test_scheme',
          debugLogs: true,
        );

        expect(config.debugLogs, equals(true));
      });
    });

    group('RustoreBillingException', () {
      test('should create exception with message', () {
        final exception = RustoreBillingException(
          'Test error',
          StackTrace.current,
        );
        expect(exception.message, equals('Test error'));
        expect(
          exception.toString(),
          equals('RustoreBillingException: Test error'),
        );
      });
    });

    group('Enums', () {
      test('RustorePurchaseState should have all expected values', () {
        expect(RustorePurchaseState.values, hasLength(7));
        expect(
          RustorePurchaseState.values,
          contains(RustorePurchaseState.created),
        );
        expect(
          RustorePurchaseState.values,
          contains(RustorePurchaseState.paid),
        );
        expect(
          RustorePurchaseState.values,
          contains(RustorePurchaseState.cancelled),
        );
      });

      test('RustorePaymentResultType should have all expected values', () {
        expect(RustorePaymentResultType.values, hasLength(4));
        expect(
          RustorePaymentResultType.values,
          contains(RustorePaymentResultType.success),
        );
        expect(
          RustorePaymentResultType.values,
          contains(RustorePaymentResultType.failure),
        );
        expect(
          RustorePaymentResultType.values,
          contains(RustorePaymentResultType.cancelled),
        );
      });
    });

    group('Platform Interface', () {
      test('should have placeholder implementation by default', () {
        expect(RustoreBillingPlatform.instance, isA<RustoreBillingPlatform>());
      });
    });
  });
}
