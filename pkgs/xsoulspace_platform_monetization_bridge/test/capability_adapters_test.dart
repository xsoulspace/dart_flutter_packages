import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_platform_monetization_bridge/xsoulspace_platform_monetization_bridge.dart';

void main() {
  test('purchases capability forwards provider instance', () {
    final provider = _FakePurchaseProvider();
    final capability = PurchasesCapabilityAdapter(provider);

    expect(capability.purchaseProvider, same(provider));
    expect(capability.capabilityName, 'monetization.purchases');
  });

  test('ads capability forwards provider instance', () {
    final provider = _FakeAdProvider();
    final capability = AdsCapabilityAdapter(provider);

    expect(capability.adProvider, same(provider));
    expect(capability.capabilityName, 'monetization.ads');
  });

  test('noop capabilities expose default no-op providers', () {
    final purchases = NoopPurchasesCapability();
    final ads = NoopAdsCapability();

    expect(purchases.purchaseProvider, isA<NoopPurchaseProvider>());
    expect(ads.adProvider, isA<NoopAdProvider>());
  });
}

final class _FakePurchaseProvider implements PurchaseProvider {
  @override
  Future<MonetizationStoreStatus> init() async =>
      MonetizationStoreStatus.loaded;

  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream =>
      const Stream<List<PurchaseDetailsModel>>.empty();

  @override
  Future<bool> isUserAuthorized() async => true;

  @override
  Future<bool> isStoreInstalled() async => true;

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(final PurchaseId productId) {
    throw UnimplementedError();
  }

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('unsupported');

  @override
  Future<RestoreResultModel> restorePurchases() async =>
      RestoreResultModel.success(const <PurchaseDetailsModel>[]);

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel purchase,
  ) async => CompletePurchaseResultModel.success();

  @override
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('unsupported');

  @override
  Future<CancelResultModel> cancel(final String purchaseOrProductId) async =>
      CancelResultModel.success();

  @override
  Future<void> openSubscriptionManagement() async {}

  @override
  Future<void> dispose() async {}
}

final class _FakeAdProvider implements AdProvider {
  @override
  Future<void> init() async {}

  @override
  Future<void> showRewardedAd({required final String adUnitId}) async {}

  @override
  Future<void> showInterstitialAd({required final String adUnitId}) async {}

  @override
  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) {
    return const SizedBox.shrink();
  }
}
