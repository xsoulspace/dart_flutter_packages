import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

void main() {
  group('RestorePurchasesCommand', () {
    late _FakeLocalDb db;
    late PurchasesLocalApi localApi;
    late SubscriptionStatusResource subscriptionStatus;

    setUp(() {
      db = _FakeLocalDb();
      localApi = PurchasesLocalApi(localDb: db);
      subscriptionStatus = SubscriptionStatusResource();
    });

    test('keeps subscribed if local active exists even on failure', () async {
      final active = PurchaseDetailsModel(
        purchaseDate: DateTime.now(),
        purchaseId: PurchaseId.fromJson('pid'),
        productId: PurchaseProductId.fromJson('prod'),
        status: PurchaseStatus.purchased,
        purchaseType: PurchaseProductType.subscription,
        expiryDate: DateTime.now().add(const Duration(days: 30)),
      );
      await localApi.saveActiveSubscription(active);

      final provider = _FakeProvider(
        restoreResult: RestoreResultModel.failure('net'),
      );
      final cmd = RestorePurchasesCommand(
        purchaseProvider: provider,
        purchasesLocalApi: localApi,
        handlePurchaseUpdateCommand: HandlePurchaseUpdateCommand(
          confirmPurchaseCommand: ConfirmPurchaseCommand(
            purchaseProvider: provider,
            activeSubscriptionResource: ActiveSubscriptionResource(),
            subscriptionStatusResource: subscriptionStatus,
            purchasePaywallErrorResource: PurchasePaywallErrorResource(),
          ),
          subscriptionStatusResource: subscriptionStatus,
          activeSubscriptionResource: ActiveSubscriptionResource(),
          purchasesLocalApi: localApi,
        ),
        subscriptionStatusResource: subscriptionStatus,
      );

      await cmd.execute();

      expect(subscriptionStatus.isSubscribed, isTrue);
    });

    test('sets free when no local active and no restored purchases', () async {
      final provider = _FakeProvider(
        restoreResult: RestoreResultModel.success(const []),
      );
      final cmd = RestorePurchasesCommand(
        purchaseProvider: provider,
        purchasesLocalApi: localApi,
        handlePurchaseUpdateCommand: HandlePurchaseUpdateCommand(
          confirmPurchaseCommand: ConfirmPurchaseCommand(
            purchaseProvider: provider,
            activeSubscriptionResource: ActiveSubscriptionResource(),
            subscriptionStatusResource: subscriptionStatus,
            purchasePaywallErrorResource: PurchasePaywallErrorResource(),
          ),
          subscriptionStatusResource: subscriptionStatus,
          activeSubscriptionResource: ActiveSubscriptionResource(),
          purchasesLocalApi: localApi,
        ),
        subscriptionStatusResource: subscriptionStatus,
      );

      await cmd.execute();
      expect(subscriptionStatus.isFree, isTrue);
    });
  });
}

class _FakeProvider implements PurchaseProvider {
  _FakeProvider({required this.restoreResult});

  final RestoreResultModel restoreResult;
  final _ctrl = StreamController<List<PurchaseDetailsModel>>.broadcast();

  @override
  Future<MonetizationStoreStatus> init() async =>
      MonetizationStoreStatus.loaded;

  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream => _ctrl.stream;

  @override
  Future<bool> isUserAuthorized() async => true;

  @override
  Future<bool> isStoreInstalled() async => true;

  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    final List<PurchaseProductId> productIds,
  ) async => [];

  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async => [];

  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) async => [];

  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async => [];

  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId productId,
  ) async => PurchaseDetailsModel(purchaseDate: DateTime.now());

  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('');

  @override
  Future<RestoreResultModel> restorePurchases() async => restoreResult;

  @override
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel purchase,
  ) async => CompletePurchaseResultModel.success();

  @override
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('');

  @override
  Future<CancelResultModel> cancel(final String purchaseOrProductId) async =>
      CancelResultModel.success();

  @override
  Future<void> openSubscriptionManagement() async {}

  @override
  Future<void> dispose() async => _ctrl.close();
}

class _FakeLocalDb implements LocalDbI {
  final Map<String, dynamic> _store = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> setItem<T>({
    required final String key,
    required final T value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) async {
    _store[key] = toJson(value);
  }

  @override
  Future<T> getItem<T>({
    required final String key,
    required final T? Function(Map<String, dynamic> p1) fromJson,
    required final T defaultValue,
  }) async {
    final raw = _store[key];
    if (raw is Map<String, dynamic>) return fromJson(raw) ?? defaultValue;
    return defaultValue;
  }

  // Unused in tests
  @override
  Future<void> setMap({
    required final String key,
    required final Map<String, dynamic> value,
  }) async {}
  @override
  Future<Map<String, dynamic>> getMap(final String key) async => {};
  @override
  Future<void> setString({
    required final String key,
    required final String value,
  }) async {}
  @override
  Future<String> getString({
    required final String key,
    final String defaultValue = '',
  }) async => defaultValue;
  @override
  Future<void> setBool({
    required final String key,
    required final bool value,
  }) async {}
  @override
  Future<bool> getBool({
    required final String key,
    final bool defaultValue = false,
  }) async => defaultValue;
  @override
  Future<void> setInt({required final String key, final int value = 0}) async {}
  @override
  Future<int> getInt({
    required final String key,
    final int defaultValue = 0,
  }) async => defaultValue;
  @override
  Future<void> setItemsList<T>({
    required final String key,
    required final List<T> value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) async {}
  @override
  Future<Iterable<T>> getItemsIterable<T>({
    required final String key,
    required final T Function(Map<String, dynamic> p1) fromJson,
    final List<T> defaultValue = const [],
  }) async => defaultValue;
  @override
  Future<void> setMapList({
    required final String key,
    required final List<Map<String, dynamic>> value,
  }) async {}
  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required final String key,
    final List<Map<String, dynamic>> defaultValue = const [],
  }) async => defaultValue;
  @override
  Future<void> setStringList({
    required final String key,
    required final List<String> value,
  }) async {}
  @override
  Future<Iterable<String>> getStringsIterable({
    required final String key,
    final List<String> defaultValue = const [],
  }) async => defaultValue;
}
