import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart' as iap;
import 'package:xsoulspace_monetization_google_apple/src/apple_native_purchase_provider.dart';
import 'package:xsoulspace_monetization_google_apple/src/google_apple_purchase_provider.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

void main() {
  group('GoogleApplePurchaseProvider', () {
    late StreamController<List<iap.PurchaseDetails>> purchaseController;
    late _FakeInAppPurchaseClient inAppPurchaseClient;
    late _FakeAppleNativePurchaseProvider appleNativeProvider;
    late GoogleApplePurchaseProvider provider;
    late bool isIOS;
    late int openSubscriptionManagementCalls;

    setUp(() async {
      GoogleApplePurchaseProvider.resetAuthorizationStateForTests();
      purchaseController =
          StreamController<List<iap.PurchaseDetails>>.broadcast();
      inAppPurchaseClient = _FakeInAppPurchaseClient(
        purchaseStream: purchaseController.stream,
      );
      appleNativeProvider = _FakeAppleNativePurchaseProvider();
      isIOS = false;
      openSubscriptionManagementCalls = 0;

      provider = GoogleApplePurchaseProvider(
        inAppPurchaseClient: inAppPurchaseClient,
        appleNativeProvider: appleNativeProvider,
        isIOS: () => isIOS,
        openSubscriptionManagement: () async {
          openSubscriptionManagementCalls += 1;
        },
      );

      await provider.init();
    });

    tearDown(() async {
      await provider.dispose();
      await purchaseController.close();
    });

    test('forwards purchase stream updates and maps purchase fields', () async {
      final pending = provider.purchaseStream.first;

      purchaseController.add([
        _iapPurchase(
          purchaseId: 'fallback_id',
          productId: 'pro_year_subscription',
          status: iap.PurchaseStatus.purchased,
          localVerificationData: jsonEncode({
            'transactionId': 'tx_1',
            'purchaseDate': 1704067200000,
            'expiresDate': 4102444800000,
            'price': 49.99,
            'currency': 'USD',
            'formattedPrice': r'$49.99',
            'appTransactionId': 'token_1',
            'type': 'Auto-Renewable Subscription',
          }),
        ),
      ]);

      final mapped = await pending;
      expect(mapped, hasLength(1));
      expect(mapped.first.purchaseId.value, 'tx_1');
      expect(mapped.first.productId.value, 'pro_year_subscription');
      expect(mapped.first.status, PurchaseStatus.purchased);
      expect(mapped.first.purchaseType, PurchaseProductType.subscription);
      expect(mapped.first.currency, 'USD');
    });

    test('getProductDetails uses in-app purchase client on non-iOS', () async {
      inAppPurchaseClient.queryProductDetailsResult =
          iap.ProductDetailsResponse(
            productDetails: [
              iap.ProductDetails(
                id: 'pro_month_subscription',
                title: 'Pro Month',
                description: 'Monthly plan',
                price: r'$9.99',
                rawPrice: 9.99,
                currencyCode: 'USD',
              ),
            ],
            notFoundIDs: [],
          );

      final result = await provider.getProductDetails([
        PurchaseProductId.fromJson('pro_month_subscription'),
      ]);

      expect(inAppPurchaseClient.queryProductDetailsCalls, 1);
      expect(result, hasLength(1));
      expect(result.first.productType, PurchaseProductType.subscription);
      expect(result.first.duration, const Duration(days: 30));
    });

    test('getProductDetails delegates to Apple provider on iOS', () async {
      isIOS = true;
      appleNativeProvider.fetchProductsResult = [
        _productDetails(
          id: 'pro_year_subscription',
          duration: const Duration(days: 365),
        ),
      ];

      final result = await provider.getProductDetails([
        PurchaseProductId.fromJson('pro_year_subscription'),
      ]);

      expect(inAppPurchaseClient.queryProductDetailsCalls, 0);
      expect(result, hasLength(1));
      expect(result.first.productId.value, 'pro_year_subscription');
    });

    test(
      'getConsumables marks user unauthorized on storekit no response',
      () async {
        inAppPurchaseClient.queryProductDetailsResult =
            iap.ProductDetailsResponse(
              productDetails: const [],
              notFoundIDs: const [],
              error: iap.IAPError(
                source: 'storekit',
                code: 'storekit_no_response',
                message: 'no response',
              ),
            );

        await expectLater(
          provider.getConsumables([PurchaseProductId.fromJson('pro_month')]),
          throwsA(isA<Exception>()),
        );

        final isAuthorized = await provider.isUserAuthorized();
        expect(isAuthorized, isFalse);
      },
    );

    test(
      'purchaseNonConsumable returns failure for product query error',
      () async {
        inAppPurchaseClient.queryProductDetailsResult =
            iap.ProductDetailsResponse(
              productDetails: const [],
              notFoundIDs: const [],
              error: iap.IAPError(
                source: 'billing',
                code: 'query_failed',
                message: 'query failed',
              ),
            );

        final result = await provider.purchaseNonConsumable(
          _productDetails(id: 'pro_month_subscription'),
        );

        expect(result.isSuccess, isFalse);
        expect(result.error, contains('query failed'));
      },
    );

    test(
      'purchaseNonConsumable returns failure when product is missing',
      () async {
        inAppPurchaseClient.queryProductDetailsResult =
            iap.ProductDetailsResponse(
              productDetails: const [],
              notFoundIDs: const [],
            );

        final result = await provider.purchaseNonConsumable(
          _productDetails(id: 'pro_month_subscription'),
        );

        expect(result.isSuccess, isFalse);
        expect(result.error, contains('Product not found'));
      },
    );

    test(
      'purchaseNonConsumable returns pending purchase model on success',
      () async {
        inAppPurchaseClient
          ..queryProductDetailsResult = iap.ProductDetailsResponse(
            productDetails: [
              iap.ProductDetails(
                id: 'pro_month_subscription',
                title: 'Pro Month',
                description: 'Monthly plan',
                price: r'$9.99',
                rawPrice: 9.99,
                currencyCode: 'USD',
              ),
            ],
            notFoundIDs: [],
          )
          ..buyNonConsumableResult = true;

        final result = await provider.purchaseNonConsumable(
          _productDetails(id: 'pro_month_subscription'),
        );

        expect(result.isSuccess, isTrue);
        expect(result.details, isNotNull);
        expect(result.details!.status, PurchaseStatus.pendingVerification);
        expect(result.details!.productId.value, 'pro_month_subscription');
        expect(inAppPurchaseClient.lastPurchaseParam, isNotNull);
      },
    );

    test('purchaseNonConsumable returns failure when buy throws', () async {
      inAppPurchaseClient
        ..queryProductDetailsResult = iap.ProductDetailsResponse(
          productDetails: [
            iap.ProductDetails(
              id: 'pro_month_subscription',
              title: 'Pro Month',
              description: 'Monthly plan',
              price: r'$9.99',
              rawPrice: 9.99,
              currencyCode: 'USD',
            ),
          ],
          notFoundIDs: [],
        )
        ..buyNonConsumableError = Exception('billing unavailable');

      final result = await provider.purchaseNonConsumable(
        _productDetails(id: 'pro_month_subscription'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('billing unavailable'));
    });

    test('completePurchase delegates to client', () async {
      final result = await provider.completePurchase(
        PurchaseVerificationDtoModel(
          transactionDate: DateTime(2025),
          purchaseId: PurchaseId.fromJson('purchase_1'),
          productId: PurchaseProductId.fromJson('pro_month_subscription'),
          status: PurchaseStatus.purchased,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(inAppPurchaseClient.completedPurchases, hasLength(1));
      expect(
        inAppPurchaseClient.completedPurchases.first.purchaseID,
        'purchase_1',
      );
    });

    test('completePurchase returns failure when client throws', () async {
      inAppPurchaseClient.completePurchaseError = Exception('complete failed');

      final result = await provider.completePurchase(
        PurchaseVerificationDtoModel(
          transactionDate: DateTime(2025),
          purchaseId: PurchaseId.fromJson('purchase_1'),
          productId: PurchaseProductId.fromJson('pro_month_subscription'),
          status: PurchaseStatus.purchased,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('complete failed'));
    });

    test('restorePurchases returns failure when client throws', () async {
      inAppPurchaseClient.restorePurchasesError = Exception('restore failed');

      final result = await provider.restorePurchases();

      expect(result.isSuccess, isFalse);
      expect(result.error, contains('restore failed'));
    });

    test('cancel delegates to Apple provider on iOS', () async {
      isIOS = true;
      appleNativeProvider.cancelResult = CancelResultModel.failure(
        'apple error',
      );

      final result = await provider.cancel('purchase_1');

      expect(result.isFailure, isTrue);
      expect(result.error, 'apple error');
      expect(openSubscriptionManagementCalls, 0);
    });

    test('cancel opens subscription management on non-iOS', () async {
      final result = await provider.cancel('purchase_1');

      expect(result.isSuccess, isTrue);
      expect(openSubscriptionManagementCalls, 1);
    });

    test('getPurchaseDetails returns stream match on non-iOS', () async {
      final pending = provider.getPurchaseDetails(PurchaseId.fromJson('tx_42'));

      purchaseController.add([
        _iapPurchase(
          purchaseId: 'fallback_id',
          productId: 'pro_year_subscription',
          status: iap.PurchaseStatus.purchased,
          localVerificationData: jsonEncode({
            'transactionId': 'tx_42',
            'purchaseDate': 1704067200000,
            'price': 49.99,
            'currency': 'USD',
            'formattedPrice': r'$49.99',
            'type': 'Non-Consumable',
          }),
        ),
      ]);

      final result = await pending;
      expect(result.purchaseId.value, 'tx_42');
      expect(result.productId.value, 'pro_year_subscription');
    });

    test('getPurchaseDetails delegates by purchase id on iOS', () async {
      isIOS = true;
      appleNativeProvider.purchaseDetailsByIdResult = PurchaseDetailsModel(
        purchaseId: PurchaseId.fromJson('apple_tx'),
        productId: PurchaseProductId.fromJson('pro_year_subscription'),
        priceId: PurchasePriceId.fromJson('pro_year_subscription'),
        status: PurchaseStatus.purchased,
        purchaseType: PurchaseProductType.subscription,
        purchaseDate: DateTime(2025),
      );

      final result = await provider.getPurchaseDetails(
        PurchaseId.fromJson('apple_tx'),
      );

      expect(result.purchaseId.value, 'apple_tx');
    });

    test('getNonConsumables filters Apple products on iOS', () async {
      isIOS = true;
      appleNativeProvider.fetchProductsResult = [
        _productDetails(id: 'consumable', type: PurchaseProductType.consumable),
        _productDetails(
          id: 'non_consumable',
          type: PurchaseProductType.nonConsumable,
        ),
        _productDetails(id: 'subscription'),
      ];

      final result = await provider.getNonConsumables([
        PurchaseProductId.fromJson('consumable'),
        PurchaseProductId.fromJson('non_consumable'),
        PurchaseProductId.fromJson('subscription'),
      ]);

      expect(result.map((final e) => e.productId.value), [
        'non_consumable',
        'subscription',
      ]);
    });

    test('getSubscriptions filters Apple products on iOS', () async {
      isIOS = true;
      appleNativeProvider.fetchProductsResult = [
        _productDetails(
          id: 'non_consumable',
          type: PurchaseProductType.nonConsumable,
        ),
        _productDetails(id: 'subscription'),
      ];

      final result = await provider.getSubscriptions([
        PurchaseProductId.fromJson('non_consumable'),
        PurchaseProductId.fromJson('subscription'),
      ]);

      expect(result, hasLength(1));
      expect(result.first.productId.value, 'subscription');
    });

    test('isStoreInstalled delegates to in-app purchase client', () async {
      inAppPurchaseClient.isAvailableResult = false;
      final result = await provider.isStoreInstalled();
      expect(result, isFalse);
    });
  });
}

class _FakeInAppPurchaseClient implements InAppPurchaseClient {
  _FakeInAppPurchaseClient({required this.purchaseStream});

  @override
  final Stream<List<iap.PurchaseDetails>> purchaseStream;

  iap.ProductDetailsResponse queryProductDetailsResult =
      iap.ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: const [],
      );
  Exception? queryProductDetailsError;
  int queryProductDetailsCalls = 0;

  bool buyNonConsumableResult = true;
  Exception? buyNonConsumableError;
  iap.PurchaseParam? lastPurchaseParam;

  Exception? completePurchaseError;
  final List<iap.PurchaseDetails> completedPurchases = [];

  Exception? restorePurchasesError;
  bool restorePurchasesCalled = false;

  bool isAvailableResult = true;

  @override
  Future<void> completePurchase(final iap.PurchaseDetails purchase) async {
    if (completePurchaseError != null) throw completePurchaseError!;
    completedPurchases.add(purchase);
  }

  @override
  Future<iap.ProductDetailsResponse> queryProductDetails(
    final Set<String> identifiers,
  ) async {
    queryProductDetailsCalls += 1;
    if (queryProductDetailsError != null) throw queryProductDetailsError!;
    return queryProductDetailsResult;
  }

  @override
  Future<bool> buyNonConsumable({
    required final iap.PurchaseParam purchaseParam,
  }) async {
    lastPurchaseParam = purchaseParam;
    if (buyNonConsumableError != null) throw buyNonConsumableError!;
    return buyNonConsumableResult;
  }

  @override
  Future<void> restorePurchases() async {
    restorePurchasesCalled = true;
    if (restorePurchasesError != null) throw restorePurchasesError!;
  }

  @override
  Future<bool> isAvailable() async => isAvailableResult;
}

class _FakeAppleNativePurchaseProvider extends AppleNativePurchaseProvider {
  List<PurchaseProductDetailsModel> fetchProductsResult = const [];
  Exception? fetchProductsError;

  PurchaseDetailsModel purchaseDetailsByIdResult = PurchaseDetailsModel(
    purchaseId: PurchaseId.fromJson('default_purchase'),
    productId: PurchaseProductId.fromJson('default_product'),
    priceId: PurchasePriceId.fromJson('default_product'),
    status: PurchaseStatus.purchased,
    purchaseType: PurchaseProductType.nonConsumable,
    purchaseDate: DateTime(2025),
  );
  Exception? purchaseDetailsByIdError;

  CancelResultModel cancelResult = CancelResultModel.success();
  Exception? cancelError;

  @override
  Future<List<PurchaseProductDetailsModel>> fetchProducts(
    final List<PurchaseProductId> productIds,
  ) async {
    if (fetchProductsError != null) throw fetchProductsError!;
    return fetchProductsResult;
  }

  @override
  Future<PurchaseDetailsModel> getPurchaseDetailsByPurchaseId(
    final PurchaseId purchaseId,
  ) async {
    if (purchaseDetailsByIdError != null) throw purchaseDetailsByIdError!;
    return purchaseDetailsByIdResult;
  }

  @override
  Future<CancelResultModel> cancelSubscription() async {
    if (cancelError != null) throw cancelError!;
    return cancelResult;
  }
}

iap.PurchaseDetails _iapPurchase({
  required final String purchaseId,
  required final String productId,
  required final iap.PurchaseStatus status,
  required final String localVerificationData,
}) => iap.PurchaseDetails(
  purchaseID: purchaseId,
  productID: productId,
  transactionDate: '1704067200000',
  status: status,
  verificationData: iap.PurchaseVerificationData(
    localVerificationData: localVerificationData,
    serverVerificationData: 'server',
    source: 'in_app_purchase',
  ),
);

PurchaseProductDetailsModel _productDetails({
  required final String id,
  final PurchaseProductType type = PurchaseProductType.subscription,
  final Duration duration = const Duration(days: 30),
}) => PurchaseProductDetailsModel(
  productId: PurchaseProductId.fromJson(id),
  priceId: PurchasePriceId.fromJson(id),
  productType: type,
  name: id,
  formattedPrice: r'$9.99',
  price: 9.99,
  currency: 'USD',
  description: 'Description',
  duration: duration,
  freeTrialDuration: PurchaseDurationModel.zero,
);
