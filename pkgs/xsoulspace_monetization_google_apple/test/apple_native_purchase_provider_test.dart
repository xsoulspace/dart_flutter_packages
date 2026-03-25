import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_google_apple/src/apple_native_purchase_provider.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.xsoulspace.monetization/purchases');
  final binaryMessenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('AppleNativePurchaseProvider', () {
    late AppleNativePurchaseProvider provider;

    setUp(() {
      provider = AppleNativePurchaseProvider();
    });

    tearDown(() {
      binaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('fetchProducts maps storekit payload to product model', () async {
      binaryMessenger.setMockMethodCallHandler(channel, (final call) async {
        expect(call.method, 'fetchProducts');
        expect(call.arguments, <String>['premium_year']);

        return <String>[
          jsonEncode(<String, dynamic>{
            'attributes': <String, dynamic>{
              'offerName': 'premium_year',
              'name': 'Premium Yearly',
              'description': <String, dynamic>{'standard': 'Yearly plan'},
              'kind': 'auto-renewable subscription',
              'isSubscription': true,
              'offers': <Map<String, dynamic>>[
                <String, dynamic>{
                  'price': 59.99,
                  'currencyCode': 'USD',
                  'priceFormatted': r'$59.99',
                  'recurringSubscriptionPeriod': 'P1Y',
                },
              ],
            },
          }),
        ];
      });

      final products = await provider.fetchProducts(<PurchaseProductId>[
        PurchaseProductId.fromJson('premium_year'),
      ]);

      expect(products, hasLength(1));
      final product = products.single;
      expect(product.productId.value, 'premium_year');
      expect(product.productType, PurchaseProductType.subscription);
      expect(product.formattedPrice, r'$59.99');
      expect(product.duration.inDays, 365);
      expect(product.hasFreeTrial, isFalse);
    });

    test(
      'purchaseProduct returns canceled when store reports cancellation',
      () async {
        binaryMessenger.setMockMethodCallHandler(channel, (final call) {
          expect(call.method, 'purchaseProduct');
          throw PlatformException(
            code: 'purchase_cancelled',
            message: 'User canceled purchase',
          );
        });

        final result = await provider.purchaseProduct(_productDetailsModel());
        expect(result.isSuccess, isTrue);
        expect(result.details, isNotNull);
        expect(result.details!.status, PurchaseStatus.canceled);
      },
    );

    test('cancelSubscription propagates platform failure', () async {
      binaryMessenger.setMockMethodCallHandler(channel, (final call) {
        expect(call.method, 'showCancelSubscriptionSheet');
        throw PlatformException(
          code: 'unavailable',
          message: 'Subscriptions are not available on this device',
        );
      });

      final result = await provider.cancelSubscription();
      expect(result.isFailure, isTrue);
      expect(result.error, contains('not available'));
    });

    test('getPurchaseDetailsByPurchaseId maps transaction payload', () async {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(days: 30));

      binaryMessenger.setMockMethodCallHandler(channel, (final call) async {
        expect(call.method, 'getPurchaseDetailsByPurchaseId');
        expect(call.arguments, 'purchase-abc');

        return jsonEncode(<String, dynamic>{
          'id': 'purchase-abc',
          'productId': 'premium_month',
          'purchaseDate': now.millisecondsSinceEpoch,
          'expiresDate': expiresAt.millisecondsSinceEpoch,
          'price': 4.99,
          'currencyCode': 'USD',
          'product': <String, dynamic>{
            'attributes': <String, dynamic>{
              'name': 'Premium Monthly',
              'kind': 'auto-renewable subscription',
              'isSubscription': true,
              'offers': <Map<String, dynamic>>[
                <String, dynamic>{
                  'priceFormatted': r'$4.99',
                  'recurringSubscriptionPeriod': 'P1M',
                },
              ],
            },
          },
        });
      });

      final details = await provider.getPurchaseDetailsByPurchaseId(
        PurchaseId.fromJson('purchase-abc'),
      );

      expect(details.purchaseId.value, 'purchase-abc');
      expect(details.productId.value, 'premium_month');
      expect(details.status, PurchaseStatus.purchased);
      expect(details.purchaseType, PurchaseProductType.subscription);
      expect(details.formattedPrice, r'$4.99');
      expect(details.duration.inDays, 30);
    });
  });
}

PurchaseProductDetailsModel _productDetailsModel() =>
    PurchaseProductDetailsModel(
      productId: PurchaseProductId.fromJson('premium_month'),
      priceId: PurchasePriceId.fromJson('premium_month'),
      productType: PurchaseProductType.subscription,
      name: 'Premium Monthly',
      formattedPrice: r'$4.99',
      price: 4.99,
      currency: 'USD',
      description: 'Monthly plan',
      duration: const Duration(days: 30),
      freeTrialDuration: PurchaseDurationModel.zero,
    );
