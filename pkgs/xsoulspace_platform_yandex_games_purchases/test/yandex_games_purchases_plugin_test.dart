import 'package:test/test.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_purchases_bridge/xsoulspace_platform_purchases_bridge.dart';
import 'package:xsoulspace_platform_yandex_games_purchases/xsoulspace_platform_yandex_games_purchases.dart';

void main() {
  test('adds purchases capability when provider is available', () async {
    final client = YandexGamesPurchasesPlatformClient(
      baseClient: _FakeBaseClient(),
      pluginConfig: YandexGamesPurchasesPluginConfig(
        purchaseProviderFactory: () =>
            _FakePurchaseProvider(status: MonetizationStoreStatus.loaded),
      ),
      defaultProviderFactory: () =>
          _FakePurchaseProvider(status: MonetizationStoreStatus.loaded),
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isSuccess, isTrue);
    expect(client.supports<PurchasesCapability>(), isTrue);
    expect(client.maybe<PurchasesCapability>(), isNotNull);
    expect(client.capabilityTypes, contains(PurchasesCapability));
    expect(client.capabilityTypes.length, greaterThanOrEqualTo(2));
  });

  test(
    'does not add purchases capability when provider is unavailable',
    () async {
      final client = YandexGamesPurchasesPlatformClient(
        baseClient: _FakeBaseClient(),
        pluginConfig: YandexGamesPurchasesPluginConfig(
          purchaseProviderFactory: () => _FakePurchaseProvider(
            status: MonetizationStoreStatus.notAvailable,
          ),
        ),
        defaultProviderFactory: () =>
            _FakePurchaseProvider(status: MonetizationStoreStatus.loaded),
      );

      final init = await client.init(const PlatformInitOptions());
      expect(init.isSuccess, isTrue);
      expect(client.supports<PurchasesCapability>(), isFalse);
    },
  );

  test('fails init when purchases are required but unavailable', () async {
    final client = YandexGamesPurchasesPlatformClient(
      baseClient: _FakeBaseClient(),
      pluginConfig: YandexGamesPurchasesPluginConfig(
        failIfUnavailable: true,
        purchaseProviderFactory: () =>
            _FakePurchaseProvider(status: MonetizationStoreStatus.notAvailable),
      ),
      defaultProviderFactory: () =>
          _FakePurchaseProvider(status: MonetizationStoreStatus.loaded),
    );

    final init = await client.init(const PlatformInitOptions());
    expect(init.isFailure, isTrue);
  });
}

final class _FakeBaseClient implements PlatformClient {
  @override
  PlatformId get platformId => PlatformId.yandexGames;

  @override
  Set<Type> get capabilityTypes => const <Type>{};

  @override
  Stream<PlatformEvent> get events => const Stream<PlatformEvent>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async {
    return PlatformInitResult.success();
  }

  @override
  T? maybe<T extends PlatformCapability>() => null;

  @override
  T require<T extends PlatformCapability>() {
    throw MissingPlatformCapabilityException(
      capabilityType: T,
      supportedCapabilities: capabilityTypes,
      behavior: MissingCapabilityBehavior.strict,
      platformId: platformId,
    );
  }

  @override
  bool supports<T extends PlatformCapability>() => false;
}

final class _FakePurchaseProvider implements PurchaseProvider {
  _FakePurchaseProvider({required this.status});

  final MonetizationStoreStatus status;

  @override
  Future<MonetizationStoreStatus> init() async => status;

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
