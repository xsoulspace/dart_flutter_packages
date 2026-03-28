import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_huawei/xsoulspace_monetization_huawei.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const iapChannel = MethodChannel('IapClient');

  late Future<dynamic> Function(MethodCall call) iapHandler;
  late List<MethodCall> iapCalls;

  setUp(() {
    iapCalls = <MethodCall>[];
    iapHandler = (_) async => throw PlatformException(code: 'unimplemented');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iapChannel, (final call) async {
          iapCalls.add(call);
          return iapHandler(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iapChannel, null);
  });

  group('init', () {
    test('enables logger and loads when initialization succeeds', () async {
      iapHandler = (final call) async {
        expect(call.method, 'enableLogger');
        return null;
      };
      final provider = HuaweiPurchaseProvider(enableLogger: true);
      addTearDown(provider.dispose);

      final result = await provider.init();

      expect(result, MonetizationStoreStatus.loaded);
      expect(iapCalls.map((final call) => call.method), <String>[
        'enableLogger',
      ]);
    });

    test(
      'returns notAvailable when sandbox is required but not active',
      () async {
        iapHandler = (final call) async {
          expect(call.method, 'isSandboxActivated');
          return _sandboxActivatedResponse(isSandboxApk: false);
        };
        final provider = HuaweiPurchaseProvider(isSandbox: true);
        addTearDown(provider.dispose);

        final result = await provider.init();

        expect(result, MonetizationStoreStatus.notAvailable);
      },
    );

    test('returns loaded when sandbox is required and active', () async {
      iapHandler = (final call) async {
        expect(call.method, 'isSandboxActivated');
        return _sandboxActivatedResponse(isSandboxApk: true);
      };
      final provider = HuaweiPurchaseProvider(isSandbox: true);
      addTearDown(provider.dispose);

      final result = await provider.init();

      expect(result, MonetizationStoreStatus.loaded);
    });
  });

  group('store availability', () {
    test(
      'isUserAuthorized returns true when environment status is 0',
      () async {
        iapHandler = (_) async => _isEnvReadyResponse(statusCode: 0);
        final provider = HuaweiPurchaseProvider();
        addTearDown(provider.dispose);

        final result = await provider.isUserAuthorized();

        expect(result, isTrue);
      },
    );

    test('isStoreInstalled returns false when platform call throws', () async {
      iapHandler = (_) async => throw PlatformException(code: 'platform_error');
      final provider = HuaweiPurchaseProvider();
      addTearDown(provider.dispose);

      final result = await provider.isStoreInstalled();

      expect(result, isFalse);
    });
  });

  group('product queries', () {
    test('getSubscriptions maps Huawei product fields', () async {
      const productId = 'sub.premium.monthly';
      iapHandler = (final call) async {
        if (call.method != 'obtainProductInfo') {
          throw PlatformException(
            code: 'unexpected_method',
            message: call.method,
          );
        }
        return _productInfoResponse(
          statusCode: 0,
          products: <Map<String, dynamic>>[
            <String, dynamic>{
              'productId': productId,
              'priceType': 2,
              'price': r'$4.99',
              'microsPrice': 4990000,
              'currency': 'USD',
              'productName': 'Premium Monthly',
              'productDesc': 'Monthly premium subscription',
              'subPeriod': 'P30D',
              'subFreeTrialPeriod': 'P7D',
            },
          ],
        );
      };
      final provider = HuaweiPurchaseProvider();
      addTearDown(provider.dispose);

      final result = await provider.getSubscriptions(<PurchaseProductId>[
        PurchaseProductId.fromJson(productId),
      ]);

      expect(result, hasLength(1));
      final product = result.first;
      expect(product.productId.value, productId);
      expect(product.priceId.value, productId);
      expect(product.productType, PurchaseProductType.subscription);
      expect(product.name, 'Premium Monthly');
      expect(product.description, 'Monthly premium subscription');
      expect(product.formattedPrice, r'$4.99');
      expect(product.price, 4990000 / 1000000);
      expect(product.currency, 'USD');
      expect(product.duration, const Duration(days: 30));
      expect(product.freeTrialDuration.days, 7);

      final call = iapCalls.singleWhere(
        (final methodCall) => methodCall.method == 'obtainProductInfo',
      );
      final args = call.arguments as Map<dynamic, dynamic>;
      expect(args['priceType'], 2);
      expect(args['skuIds'], <String>[productId]);
    });

    test('getProductDetails throws when Huawei status is non-zero', () async {
      iapHandler = (_) async => _productInfoResponse(
        statusCode: 500,
        products: const <Map<String, dynamic>>[],
      );
      final provider = HuaweiPurchaseProvider();
      addTearDown(provider.dispose);

      expect(
        () => provider.getProductDetails(<PurchaseProductId>[
          PurchaseProductId.fromJson('broken.sku'),
        ]),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('purchase flow', () {
    test('purchaseNonConsumable emits purchase details to stream', () async {
      const purchaseTimeMs = 1735689600000;
      final product = PurchaseProductDetailsModel(
        freeTrialDuration: PurchaseDurationModel(days: 7),
        productId: PurchaseProductId.fromJson('sub.premium.monthly'),
        priceId: PurchasePriceId.fromJson('sub.premium.monthly'),
        productType: PurchaseProductType.subscription,
        name: 'Premium Monthly',
        formattedPrice: r'$4.99',
        price: 4.99,
        currency: 'USD',
        duration: const Duration(days: 30),
      );

      iapHandler = (final call) async {
        if (call.method != 'createPurchaseIntent') {
          throw PlatformException(
            code: 'unexpected_method',
            message: call.method,
          );
        }
        return _purchaseIntentResponse(
          purchaseData: _purchaseData(
            orderId: 'order-1',
            productId: 'sub.premium.monthly',
            purchaseToken: 'token-1',
            purchaseTimeMs: purchaseTimeMs,
            purchaseState: 0,
            kind: 2,
          ),
        );
      };
      final provider = HuaweiPurchaseProvider();
      addTearDown(provider.dispose);

      final streamEvent = provider.purchaseStream.first;
      final result = await provider.purchaseNonConsumable(product);
      final streamBatch = await streamEvent;

      expect(result.isSuccess, isTrue);
      final details = result.details!;
      expect(details.purchaseId.value, 'order-1');
      expect(details.productId.value, 'sub.premium.monthly');
      expect(details.status, PurchaseStatus.purchased);
      expect(details.purchaseType, PurchaseProductType.subscription);
      expect(
        details.expiryDate,
        DateTime.fromMillisecondsSinceEpoch(
          purchaseTimeMs,
        ).add(const Duration(days: 30)),
      );

      expect(streamBatch, hasLength(1));
      expect(streamBatch.single.purchaseId.value, 'order-1');

      final call = iapCalls.singleWhere(
        (final methodCall) => methodCall.method == 'createPurchaseIntent',
      );
      final args = call.arguments as Map<dynamic, dynamic>;
      expect(args['priceType'], 2);
      expect(args['productId'], 'sub.premium.monthly');
    });

    test(
      'restorePurchases queries all Huawei product types and merges data',
      () async {
        iapHandler = (final call) async {
          if (call.method != 'obtainOwnedPurchases') {
            throw PlatformException(
              code: 'unexpected_method',
              message: call.method,
            );
          }

          final args = call.arguments as Map<dynamic, dynamic>;
          final priceType = args['priceType'] as int;

          return switch (priceType) {
            0 => _ownedPurchasesResponse(
              purchases: <Map<String, dynamic>>[
                _purchaseData(
                  orderId: 'consumable-order',
                  productId: 'coins.100',
                  purchaseToken: 'token-c',
                  purchaseTimeMs: 1735689600000,
                  purchaseState: 0,
                  kind: 0,
                ),
              ],
            ),
            1 => _ownedPurchasesResponse(
              returnCode: '1001',
              purchases: const <Map<String, dynamic>>[],
            ),
            2 => _ownedPurchasesResponse(
              purchases: <Map<String, dynamic>>[
                _purchaseData(
                  orderId: 'subscription-order',
                  productId: 'sub.monthly',
                  purchaseToken: 'token-s',
                  purchaseTimeMs: 1735776000000,
                  purchaseState: 0,
                  kind: 2,
                  expirationDateMs: 1738368000000,
                ),
              ],
            ),
            _ => throw PlatformException(code: 'bad_price_type'),
          };
        };
        final provider = HuaweiPurchaseProvider();
        addTearDown(provider.dispose);

        final streamEvent = provider.purchaseStream.first;
        final result = await provider.restorePurchases();
        final streamBatch = await streamEvent;

        expect(result.isSuccess, isTrue);
        expect(result.restoredPurchases, hasLength(2));
        expect(
          result.restoredPurchases.map((final item) => item.purchaseId.value),
          containsAll(<String>['consumable-order', 'subscription-order']),
        );
        expect(streamBatch, hasLength(2));

        final calledPriceTypes = iapCalls
            .where((final call) => call.method == 'obtainOwnedPurchases')
            .map((final call) {
              final args = call.arguments as Map<dynamic, dynamic>;
              return args['priceType'];
            })
            .toList();
        expect(calledPriceTypes, <int>[0, 1, 2]);
      },
    );

    test(
      'getPurchaseDetails finds purchase across all Huawei price types',
      () async {
        iapHandler = (final call) async {
          if (call.method != 'obtainOwnedPurchases') {
            throw PlatformException(
              code: 'unexpected_method',
              message: call.method,
            );
          }
          final args = call.arguments as Map<dynamic, dynamic>;
          final priceType = args['priceType'] as int;

          if (priceType == 2) {
            return _ownedPurchasesResponse(
              purchases: <Map<String, dynamic>>[
                _purchaseData(
                  orderId: 'target-order',
                  productId: 'sub.monthly',
                  purchaseToken: 'token-target',
                  purchaseTimeMs: 1735776000000,
                  purchaseState: 0,
                  kind: 2,
                  expirationDateMs: 1738368000000,
                ),
              ],
            );
          }
          return _ownedPurchasesResponse(
            purchases: const <Map<String, dynamic>>[],
          );
        };
        final provider = HuaweiPurchaseProvider();
        addTearDown(provider.dispose);

        final details = await provider.getPurchaseDetails(
          PurchaseId.fromJson('target-order'),
        );

        expect(details.purchaseId.value, 'target-order');
        expect(details.productId.value, 'sub.monthly');
        expect(details.purchaseType, PurchaseProductType.subscription);
        expect(
          details.expiryDate,
          DateTime.fromMillisecondsSinceEpoch(1738368000000),
        );

        final calledPriceTypes = iapCalls
            .where((final call) => call.method == 'obtainOwnedPurchases')
            .map((final call) {
              final args = call.arguments as Map<dynamic, dynamic>;
              return args['priceType'];
            })
            .toList();
        expect(calledPriceTypes, <int>[0, 1, 2]);
      },
    );
  });

  group('complete purchase', () {
    test('consumes consumables using Huawei consumeOwnedPurchase', () async {
      iapHandler = (final call) async {
        expect(call.method, 'consumeOwnedPurchase');
        return _consumeOwnedPurchaseResponse(returnCode: '0');
      };
      final provider = HuaweiPurchaseProvider();
      addTearDown(provider.dispose);

      final result = await provider.completePurchase(
        PurchaseVerificationDtoModel(
          transactionDate: DateTime.utc(2026),
          purchaseToken: 'token-consumable',
        ),
      );

      expect(result.isSuccess, isTrue);
      final call = iapCalls.singleWhere(
        (final methodCall) => methodCall.method == 'consumeOwnedPurchase',
      );
      final args = call.arguments as Map<dynamic, dynamic>;
      expect(args['purchaseToken'], 'token-consumable');
    });

    test('does not consume non-consumable purchases', () async {
      iapHandler = (_) async =>
          throw PlatformException(code: 'should_not_call');
      final provider = HuaweiPurchaseProvider();
      addTearDown(provider.dispose);

      final result = await provider.completePurchase(
        PurchaseVerificationDtoModel(
          transactionDate: DateTime.utc(2026),
          productType: PurchaseProductType.nonConsumable,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(
        iapCalls.where((final call) => call.method == 'consumeOwnedPurchase'),
        isEmpty,
      );
    });
  });

  group('subscription management', () {
    test(
      'openSubscriptionManagement starts Huawei subscription manager activity',
      () async {
        iapHandler = (final call) async {
          expect(call.method, 'startIapActivity');
          return null;
        };
        final provider = HuaweiPurchaseProvider();
        addTearDown(provider.dispose);

        await provider.openSubscriptionManagement();

        final call = iapCalls.singleWhere(
          (final methodCall) => methodCall.method == 'startIapActivity',
        );
        final args = call.arguments as Map<dynamic, dynamic>;
        expect(args['type'], 2);
      },
    );

    test(
      'cancel delegates to subscription management and returns success',
      () async {
        iapHandler = (final call) async {
          expect(call.method, 'startIapActivity');
          return null;
        };
        final provider = HuaweiPurchaseProvider();
        addTearDown(provider.dispose);

        final result = await provider.cancel('ignored-by-huawei');

        expect(result.isSuccess, isTrue);
        expect(
          iapCalls.where((final call) => call.method == 'startIapActivity'),
          hasLength(1),
        );
      },
    );
  });
}

String _isEnvReadyResponse({required final int statusCode}) =>
    jsonEncode(<String, dynamic>{
      'returnCode': statusCode == 0 ? '0' : '1',
      'status': <String, dynamic>{
        'statusCode': statusCode,
        'statusMessage': statusCode == 0 ? 'OK' : 'ERROR',
      },
    });

String _sandboxActivatedResponse({required final bool isSandboxApk}) =>
    jsonEncode(<String, dynamic>{
      'returnCode': '0',
      'isSandboxApk': isSandboxApk,
      'isSandboxUser': true,
      'status': <String, dynamic>{'statusCode': 0, 'statusMessage': 'OK'},
    });

String _productInfoResponse({
  required final int statusCode,
  required final List<Map<String, dynamic>> products,
}) => jsonEncode(<String, dynamic>{
  'returnCode': statusCode == 0 ? '0' : '1',
  'status': <String, dynamic>{
    'statusCode': statusCode,
    'statusMessage': statusCode == 0 ? 'OK' : 'ERROR',
  },
  'productInfoList': products,
});

String _purchaseIntentResponse({
  required final Map<String, dynamic> purchaseData,
}) => jsonEncode(<String, dynamic>{
  'returnCode': '0',
  'inAppPurchaseData': jsonEncode(purchaseData),
});

String _ownedPurchasesResponse({
  required final List<Map<String, dynamic>> purchases, final String returnCode = '0',
}) => jsonEncode(<String, dynamic>{
  'returnCode': returnCode,
  'inAppPurchaseDataList': purchases.map(jsonEncode).toList(),
  'itemList': purchases
      .map((final purchase) => purchase['productId'])
      .whereType<String>()
      .toList(),
});

String _consumeOwnedPurchaseResponse({required final String returnCode}) =>
    jsonEncode(<String, dynamic>{'returnCode': returnCode});

Map<String, dynamic> _purchaseData({
  required final String orderId,
  required final String productId,
  required final String purchaseToken,
  required final int purchaseTimeMs,
  required final int purchaseState,
  required final int kind,
  final int? expirationDateMs,
}) => <String, dynamic>{
  'orderId': orderId,
  'productId': productId,
  'purchaseToken': purchaseToken,
  'purchaseTime': purchaseTimeMs,
  'purchaseState': purchaseState,
  'kind': kind,
  'currency': 'USD',
  if (expirationDateMs != null) 'expirationDate': expirationDateMs,
};
