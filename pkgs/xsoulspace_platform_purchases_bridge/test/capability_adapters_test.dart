import 'package:test/test.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_platform_purchases_bridge/xsoulspace_platform_purchases_bridge.dart';

void main() {
  test('purchases capability forwards provider instance', () {
    final provider = _FakePurchaseProvider();
    final capability = PurchasesCapabilityAdapter(provider);

    expect(capability.purchaseProvider, same(provider));
    expect(capability.capabilityName, 'monetization.purchases');
  });

  test('noop purchases capability exposes default no-op provider', () {
    final purchases = NoopPurchasesCapability();

    expect(purchases.purchaseProvider, isA<NoopPurchaseProvider>());
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
    List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    List<PurchaseProductId> productIds,
  ) async => const <PurchaseProductDetailsModel>[];

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(PurchaseId productId) {
    throw UnimplementedError();
  }

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('unsupported');

  @override
  Future<RestoreResultModel> restorePurchases() async =>
      RestoreResultModel.success(const <PurchaseDetailsModel>[]);

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    PurchaseVerificationDtoModel purchase,
  ) async => CompletePurchaseResultModel.success();

  @override
  Future<PurchaseResultModel> subscribe(
    PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('unsupported');

  @override
  Future<CancelResultModel> cancel(String purchaseOrProductId) async =>
      CancelResultModel.success();

  @override
  Future<void> openSubscriptionManagement() async {}

  @override
  Future<void> dispose() async {}
}
