import 'dart:async';

import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

class FakeLocalDb implements LocalDbI {
  final Map<String, dynamic> _store = {};
  @override
  Future<void> init() async {}
  @override
  Future<void> clear() async => _store.clear();
  @override
  Future<void> clearKey({required String key}) async =>
      _store.remove(key);
  @override
  Future<void> setMap({
    required String key,
    required Map<String, dynamic> value,
  }) async => _store[key] = value;
  @override
  Future<Map<String, dynamic>> getMap(String key) async =>
      (_store[key] as Map<String, dynamic>?) ?? <String, dynamic>{};
  @override
  Future<void> setString({
    required String key,
    required String value,
  }) async => _store[key] = value;
  @override
  Future<String> getString({
    required String key,
    String defaultValue = '',
  }) async => (_store[key] as String?) ?? defaultValue;
  @override
  Future<void> setBool({
    required String key,
    required bool value,
  }) async => _store[key] = value;
  @override
  Future<bool> getBool({
    required String key,
    bool defaultValue = false,
  }) async => (_store[key] as bool?) ?? defaultValue;
  @override
  Future<void> setInt({required String key, int value = 0}) async =>
      _store[key] = value;
  @override
  Future<int> getInt({
    required String key,
    int defaultValue = 0,
  }) async => (_store[key] as int?) ?? defaultValue;
  @override
  Future<void> setItem<T>({
    required String key,
    required T value,
    required Map<String, dynamic> Function(T) toJson,
  }) async => _store[key] = toJson(value);
  @override
  Future<T> getItem<T>({
    required String key,
    required T? Function(Map<String, dynamic>) fromJson,
    required T defaultValue,
  }) async {
    final raw = _store[key];
    if (raw is Map<String, dynamic>) return fromJson(raw) ?? defaultValue;
    return defaultValue;
  }

  @override
  Future<void> setItemsList<T>({
    required String key,
    required List<T> value,
    required Map<String, dynamic> Function(T) toJson,
  }) async => _store[key] = value.map(toJson).toList();
  @override
  Future<Iterable<T>> getItemsIterable<T>({
    required String key,
    required T Function(Map<String, dynamic>) fromJson,
    List<T> defaultValue = const [],
  }) async {
    final raw = _store[key];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().map(fromJson);
    }
    return defaultValue;
  }

  @override
  Future<void> setMapList({
    required String key,
    required List<Map<String, dynamic>> value,
  }) async => _store[key] = value;
  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required String key,
    List<Map<String, dynamic>> defaultValue = const [],
  }) async {
    final raw = _store[key];
    if (raw is List) return raw.whereType<Map<String, dynamic>>();
    return defaultValue;
  }

  @override
  Future<void> setStringList({
    required String key,
    required List<String> value,
  }) async => _store[key] = value;
  @override
  Future<Iterable<String>> getStringsIterable({
    required String key,
    List<String> defaultValue = const [],
  }) async {
    final raw = _store[key];
    if (raw is List) return raw.whereType<String>();
    return defaultValue;
  }
}

class FakeProvider implements PurchaseProvider {
  FakeProvider({
    this.initStatus = MonetizationStoreStatus.loaded,
    this.authorized = true,
    this.installed = true,
    this.restoreResult,
    this.subscribeResult,
    this.completeResult,
    this.cancelResult,
    this.subscriptions = const [],
    this.purchaseDetails,
  });

  final MonetizationStoreStatus initStatus;
  final bool authorized;
  final bool installed;
  final RestoreResultModel? restoreResult;
  final PurchaseResultModel? subscribeResult;
  final CompletePurchaseResultModel? completeResult;
  final CancelResultModel? cancelResult;
  final List<PurchaseProductDetailsModel> subscriptions;
  final PurchaseDetailsModel? purchaseDetails;

  final _ctrl = StreamController<List<PurchaseDetailsModel>>.broadcast();
  int completeCalls = 0;
  int subscribeCalls = 0;
  int cancelCalls = 0;

  @override
  Future<MonetizationStoreStatus> init() async => initStatus;
  @override
  Stream<List<PurchaseDetailsModel>> get purchaseStream => _ctrl.stream;
  @override
  Future<bool> isUserAuthorized() async => authorized;
  @override
  Future<bool> isStoreInstalled() async => installed;
  @override
  Future<List<PurchaseProductDetailsModel>> getConsumables(
    List<PurchaseProductId> productIds,
  ) async => [];
  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    List<PurchaseProductId> productIds,
  ) async => [];
  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    List<PurchaseProductId> productIds,
  ) async => subscriptions;
  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    List<PurchaseProductId> productIds,
  ) async => subscriptions;
  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    PurchaseId productId,
  ) async => purchaseDetails ?? purchase(active: true);
  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('');
  @override
  Future<RestoreResultModel> restorePurchases() async =>
      restoreResult ?? RestoreResultModel.success(const []);
  @override
  Future<CompletePurchaseResultModel> completePurchase(
    PurchaseVerificationDtoModel purchase,
  ) async {
    completeCalls++;
    return completeResult ?? CompletePurchaseResultModel.success();
  }

  @override
  Future<PurchaseResultModel> subscribe(
    PurchaseProductDetailsModel productDetails,
  ) async {
    subscribeCalls++;
    return subscribeResult ?? PurchaseResultModel.failure('');
  }

  @override
  Future<CancelResultModel> cancel(String purchaseOrProductId) async {
    cancelCalls++;
    return cancelResult ?? CancelResultModel.success();
  }

  @override
  Future<void> openSubscriptionManagement() async {}
  @override
  Future<void> dispose() async => _ctrl.close();
}

PurchaseDetailsModel purchase({
  bool active = false,
  bool pendingConfirmation = false,
  bool cancelled = false,
  PurchaseProductType type = PurchaseProductType.subscription,
}) {
  final status = pendingConfirmation
      ? PurchaseStatus.pendingVerification
      : cancelled
      ? PurchaseStatus.canceled
      : PurchaseStatus.purchased;
  return PurchaseDetailsModel(
    purchaseDate: DateTime.now(),
    status: status,
    purchaseType: type,
    duration: type == PurchaseProductType.subscription
        ? const Duration(days: 30)
        : Duration.zero,
    expiryDate: active ? DateTime.now().add(const Duration(days: 30)) : null,
  );
}
