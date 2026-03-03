import 'dart:async';

import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_ysdk_games_js/xsoulspace_ysdk_games_js.dart';

/// Purchase provider backed by Yandex Games web payments API.
class YandexGamesPurchaseProvider implements PurchaseProvider {
  YandexGamesPurchaseProvider({
    final Future<YsdkClient> Function({bool signed})? initClient,
    this.signed = false,
  }) : _initClient = initClient ?? YandexGames.init;

  final Future<YsdkClient> Function({bool signed}) _initClient;
  final bool signed;

  final StreamController<List<PurchaseDetailsModel>> _purchaseController =
      StreamController<List<PurchaseDetailsModel>>.broadcast();

  YsdkClient? _client;
  YsdkPaymentsClient? _payments;

  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream =>
      _purchaseController.stream;

  @override
  Future<MonetizationStoreStatus> init() async {
    try {
      _client = await _initClient(signed: signed);
      _payments = _client!.payments;
      return MonetizationStoreStatus.loaded;
    } on Object {
      return MonetizationStoreStatus.notAvailable;
    }
  }

  @override
  Future<bool> isUserAuthorized() async {
    final client = _client;
    if (client == null) {
      return false;
    }

    try {
      final player = await client.getPlayerUnsigned();
      return (player as dynamic).isAuthorized() as bool;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> isStoreInstalled() async => _payments != null;

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    final details = await getProductDetails(productIds);
    return details
        .where(
          (final item) => item.productType == PurchaseProductType.consumable,
        )
        .toList(growable: false);
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async {
    final details = await getProductDetails(productIds);
    return details
        .where(
          (final item) => item.productType == PurchaseProductType.nonConsumable,
        )
        .toList(growable: false);
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) async {
    final payments = _requirePayments();
    final catalog = await payments.getCatalog();
    if (productIds.isEmpty) {
      return catalog.map(_mapProduct).toList(growable: false);
    }

    final requested = productIds.map((final id) => id.value).toSet();
    return catalog
        .where((final item) => requested.contains(item.id))
        .map(_mapProduct)
        .toList(growable: false);
  }

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async {
    final details = await getProductDetails(productIds);
    return details
        .where(
          (final item) => item.productType == PurchaseProductType.subscription,
        )
        .toList(growable: false);
  }

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId productId,
  ) async {
    final purchases = await _getPurchases();
    for (final purchase in purchases) {
      if (purchase.purchaseId.value == productId.value ||
          purchase.productId.value == productId.value) {
        return purchase;
      }
    }

    throw StateError('Purchase not found: ${productId.value}');
  }

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async {
    final payments = _requirePayments();

    try {
      if (signed) {
        final signature =
            await (payments as dynamic).purchaseSigned(
                  id: productDetails.productId.value,
                )
                as SignatureModel;
        final details = PurchaseDetailsModel(
          purchaseDate: DateTime.now().toUtc(),
          purchaseId: PurchaseId.fromJson(productDetails.productId.value),
          productId: productDetails.productId,
          priceId: productDetails.priceId,
          status: PurchaseStatus.pendingVerification,
          purchaseType: productDetails.productType,
          source: 'yandex_games:signed',
          localVerificationData: signature.signature,
          serverVerificationData: signature.signature,
          name: productDetails.name,
          formattedPrice: productDetails.formattedPrice,
          price: productDetails.price,
          currency: productDetails.currency,
        );
        _purchaseController.add(<PurchaseDetailsModel>[details]);
        return PurchaseResultModel.success(details);
      }

      final purchase =
          await (payments as dynamic).purchaseUnsigned(
                id: productDetails.productId.value,
              )
              as PurchaseModel;
      final details = _mapPurchase(
        purchase: purchase,
        productDetails: productDetails,
        status: PurchaseStatus.purchased,
      );
      _purchaseController.add(<PurchaseDetailsModel>[details]);
      return PurchaseResultModel.success(details);
    } on Object catch (error) {
      return PurchaseResultModel.failure(error.toString());
    }
  }

  @override
  Future<RestoreResultModel> restorePurchases() async {
    try {
      final purchases = await _getPurchases();
      return RestoreResultModel.success(purchases);
    } on Object catch (error) {
      return RestoreResultModel.failure(error.toString());
    }
  }

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel purchase,
  ) async {
    final payments = _requirePayments();
    final token = purchase.purchaseToken ?? '';

    if (token.isEmpty) {
      return CompletePurchaseResultModel.success();
    }

    try {
      await (payments as dynamic).consumePurchase(token);
      return CompletePurchaseResultModel.success();
    } on Object catch (error) {
      return CompletePurchaseResultModel.failure(error.toString());
    }
  }

  @override
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel productDetails,
  ) {
    return purchaseNonConsumable(
      PurchaseProductDetailsModel(
        freeTrialDuration: productDetails.freeTrialDuration,
        productId: productDetails.productId,
        priceId: productDetails.priceId,
        productType: PurchaseProductType.subscription,
        name: productDetails.name,
        formattedPrice: productDetails.formattedPrice,
        price: productDetails.price,
        currency: productDetails.currency,
        description: productDetails.description,
        duration: productDetails.duration,
      ),
    );
  }

  @override
  Future<CancelResultModel> cancel(final String purchaseOrProductId) async {
    return CancelResultModel.failure(
      'Cancel is not supported in Yandex Games.',
    );
  }

  @override
  Future<void> openSubscriptionManagement() async {}

  @override
  Future<void> dispose() async {
    await _purchaseController.close();
  }

  YsdkPaymentsClient _requirePayments() {
    final payments = _payments;
    if (payments == null) {
      throw StateError(
        'YandexGamesPurchaseProvider.init() must be called first.',
      );
    }
    return payments;
  }

  Future<List<PurchaseDetailsModel>> _getPurchases() async {
    final payments = _requirePayments();
    if (signed) {
      return const <PurchaseDetailsModel>[];
    }

    final purchases = await payments.getPurchasesUnsigned();
    return purchases
        .map((final item) {
          final details = _mapPurchase(
            purchase: item,
            productDetails: PurchaseProductDetailsModel(
              freeTrialDuration: PurchaseDurationModel.zero,
              productId: PurchaseProductId.fromJson(item.productId),
              priceId: PurchasePriceId.fromJson(item.productId),
              productType: _inferProductType(item.productId),
              name: item.productId,
              formattedPrice: '',
              price: 0,
              currency: '',
            ),
            status: PurchaseStatus.purchased,
          );
          return details;
        })
        .toList(growable: false);
  }

  PurchaseProductDetailsModel _mapProduct(final ProductModel item) {
    return PurchaseProductDetailsModel(
      freeTrialDuration: PurchaseDurationModel.zero,
      productId: PurchaseProductId.fromJson(item.id),
      priceId: PurchasePriceId.fromJson(item.id),
      productType: _inferProductType(item.id),
      name: item.title,
      formattedPrice: item.price,
      price: double.tryParse(item.priceValue) ?? 0,
      currency: item.priceCurrencyCode,
      description: item.description,
    );
  }

  PurchaseDetailsModel _mapPurchase({
    required final PurchaseModel purchase,
    required final PurchaseProductDetailsModel productDetails,
    required final PurchaseStatus status,
  }) {
    return PurchaseDetailsModel(
      purchaseDate: DateTime.now().toUtc(),
      purchaseId: PurchaseId.fromJson(purchase.purchaseToken),
      productId: PurchaseProductId.fromJson(purchase.productId),
      priceId: productDetails.priceId,
      status: status,
      purchaseType: productDetails.productType,
      localVerificationData: purchase.purchaseToken,
      serverVerificationData: purchase.purchaseToken,
      source: 'yandex_games',
      name: productDetails.name,
      formattedPrice: productDetails.formattedPrice,
      price: productDetails.price,
      currency: productDetails.currency,
      purchaseToken: purchase.purchaseToken,
    );
  }

  PurchaseProductType _inferProductType(final String productId) {
    final lower = productId.toLowerCase();
    if (lower.contains('sub')) {
      return PurchaseProductType.subscription;
    }
    if (lower.contains('consum')) {
      return PurchaseProductType.consumable;
    }
    return PurchaseProductType.nonConsumable;
  }
}
