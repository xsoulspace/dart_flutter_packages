import 'dart:async';

import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

class FakeLocalDb implements LocalDbI {
  final Map<String, dynamic> _store = {};
  @override
  Future<void> init() async {}
  @override
  Future<void> setMap({
    required final String key,
    required final Map<String, dynamic> value,
  }) async => _store[key] = value;
  @override
  Future<Map<String, dynamic>> getMap(final String key) async =>
      (_store[key] as Map<String, dynamic>?) ?? <String, dynamic>{};
  @override
  Future<void> setString({
    required final String key,
    required final String value,
  }) async => _store[key] = value;
  @override
  Future<String> getString({
    required final String key,
    final String defaultValue = '',
  }) async => (_store[key] as String?) ?? defaultValue;
  @override
  Future<void> setBool({
    required final String key,
    required final bool value,
  }) async => _store[key] = value;
  @override
  Future<bool> getBool({
    required final String key,
    final bool defaultValue = false,
  }) async => (_store[key] as bool?) ?? defaultValue;
  @override
  Future<void> setInt({required final String key, final int value = 0}) async =>
      _store[key] = value;
  @override
  Future<int> getInt({
    required final String key,
    final int defaultValue = 0,
  }) async => (_store[key] as int?) ?? defaultValue;
  @override
  Future<void> setItem<T>({
    required final String key,
    required final T value,
    required final Map<String, dynamic> Function(T) toJson,
  }) async => _store[key] = toJson(value);
  @override
  Future<T> getItem<T>({
    required final String key,
    required final T? Function(Map<String, dynamic>) fromJson,
    required final T defaultValue,
  }) async {
    final raw = _store[key];
    if (raw is Map<String, dynamic>) return fromJson(raw) ?? defaultValue;
    return defaultValue;
  }

  @override
  Future<void> setItemsList<T>({
    required final String key,
    required final List<T> value,
    required final Map<String, dynamic> Function(T) toJson,
  }) async => _store[key] = value.map(toJson).toList();
  @override
  Future<Iterable<T>> getItemsIterable<T>({
    required final String key,
    required final T Function(Map<String, dynamic>) fromJson,
    final List<T> defaultValue = const [],
  }) async {
    final raw = _store[key];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().map(fromJson);
    }
    return defaultValue;
  }

  @override
  Future<void> setMapList({
    required final String key,
    required final List<Map<String, dynamic>> value,
  }) async => _store[key] = value;
  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required final String key,
    final List<Map<String, dynamic>> defaultValue = const [],
  }) async {
    final raw = _store[key];
    if (raw is List) return raw.whereType<Map<String, dynamic>>();
    return defaultValue;
  }

  @override
  Future<void> setStringList({
    required final String key,
    required final List<String> value,
  }) async => _store[key] = value;
  @override
  Future<Iterable<String>> getStringsIterable({
    required final String key,
    final List<String> defaultValue = const [],
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
  });

  final MonetizationStoreStatus initStatus;
  final bool authorized;
  final bool installed;
  final RestoreResultModel? restoreResult;
  final PurchaseResultModel? subscribeResult;
  final CompletePurchaseResultModel? completeResult;
  final CancelResultModel? cancelResult;
  final List<PurchaseProductDetailsModel> subscriptions;

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
    final List<PurchaseProductId> productIds,
  ) async => [];
  @override
  Future<List<PurchaseProductDetailsModel>> getNonConsumables(
    final List<PurchaseProductId> productIds,
  ) async => [];
  @override
  Future<List<PurchaseProductDetailsModel>> getProductDetails(
    final List<PurchaseProductId> productIds,
  ) async => subscriptions;
  @override
  Future<List<PurchaseProductDetailsModel>> getSubscriptions(
    final List<PurchaseProductId> productIds,
  ) async => subscriptions;
  @override
  Future<PurchaseDetailsModel> getPurchaseDetails(
    final PurchaseId productId,
  ) async => PurchaseDetailsModel(purchaseDate: DateTime.now());
  @override
  Future<PurchaseResultModel> purchaseNonConsumable(
    final PurchaseProductDetailsModel productDetails,
  ) async => PurchaseResultModel.failure('');
  @override
  Future<RestoreResultModel> restorePurchases() async =>
      restoreResult ?? RestoreResultModel.success(const []);
  @override
  Future<CompletePurchaseResultModel> completePurchase(
    final PurchaseVerificationDtoModel purchase,
  ) async {
    completeCalls++;
    return completeResult ?? CompletePurchaseResultModel.success();
  }

  @override
  Future<PurchaseResultModel> subscribe(
    final PurchaseProductDetailsModel productDetails,
  ) async {
    subscribeCalls++;
    return subscribeResult ?? PurchaseResultModel.failure('');
  }

  @override
  Future<CancelResultModel> cancel(final String purchaseOrProductId) async {
    cancelCalls++;
    return cancelResult ?? CancelResultModel.success();
  }

  @override
  Future<void> openSubscriptionManagement() async {}
  @override
  Future<void> dispose() async => _ctrl.close();
}

PurchaseDetailsModel purchase({
  final bool active = false,
  final bool pending = false,
  final bool pendingConfirmation = false,
  final bool cancelled = false,
  final PurchaseProductType type = PurchaseProductType.subscription,
}) {
  final status = pending
      ? PurchaseStatus.pending
      : pendingConfirmation
      ? PurchaseStatus.pendingConfirmation
      : cancelled
      ? PurchaseStatus.canceled
      : PurchaseStatus.purchased;
  return PurchaseDetailsModel(
    purchaseDate: DateTime.now(),
    status: status,
    purchaseType: type,
    expiryDate: active ? DateTime.now().add(const Duration(days: 30)) : null,
  );
}
