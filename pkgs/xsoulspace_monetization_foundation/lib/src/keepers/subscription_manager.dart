import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../purchases/purchase_manager.dart';
import 'monetization_utils.dart';

/// Represents the state of user access to premium features.
enum SubscriptionManagerStatus { free, subscribed, pending }

enum MonetizationStatus { loading, notAvailable, storeNotAuthorized, loaded }

@stateDistributor
class MonetizationStatusResource extends ChangeNotifier {
  MonetizationStatusResource(this._type);
  MonetizationType _type;
  MonetizationType get type => _type;
  void setType(final MonetizationType value) {
    _type = value;
    notifyListeners();
  }

  MonetizationStatus _status = MonetizationStatus.loading;
  bool get isInitialized => _status == MonetizationStatus.loaded;
  MonetizationStatus get status => _status;
  void setStatus(final MonetizationStatus value) {
    _status = value;
    notifyListeners();
  }
}

/// {@template subscription_manager}
/// Manages the state of user subscription access to premium features.
/// {@endtemplate}
class SubscriptionManager extends ChangeNotifier {
  SubscriptionManager({
    required this.purchaseManager,
    required this.monetizationTypeResource,
    required this.productIds,
  });
  final List<PurchaseProductId> productIds;
  final PurchaseManager purchaseManager;
  final MonetizationStatusResource monetizationTypeResource;

  PurchaseDetailsModel? _activeSubscription;
  PurchaseDetailsModel? get activeSubscription => _activeSubscription;
  void setActiveSubscription(final PurchaseDetailsModel? value) {
    _activeSubscription = value;
    notifyListeners();
  }

  SubscriptionManagerStatus _state = SubscriptionManagerStatus.free;
  void _setSubscriptionAsFree() {
    _activeSubscription = null;
    _state = SubscriptionManagerStatus.free;
    notifyListeners();
  }

  PurchaseProductDetailsModel? getSubscription(final PurchaseProductId id) =>
      subscriptions.value.firstWhereOrNull((final e) => e.productId == id);
  bool get isLoading => state == SubscriptionManagerStatus.pending;

  /// The current state of user access.
  SubscriptionManagerStatus get state =>
      monetizationTypeResource.type == MonetizationType.free
      ? SubscriptionManagerStatus.subscribed
      : _state;

  LoadableContainer<List<PurchaseProductDetailsModel>> subscriptions =
      const LoadableContainer(value: []);
  var _isInitialized = false;
  bool get isInitialized => _isInitialized;
  Future<void> init() async {
    if (_isInitialized) return;
    await getSubscriptions();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> getSubscriptions() async {
    try {
      subscriptions = LoadableContainer.loaded(
        await purchaseManager.getSubscriptions(productIds),
      );
      notifyListeners();
    } on PlatformException catch (e, stackTrace) {
      debugPrint('Failed to get subscriptions: $e $stackTrace');
      if (e.code == 'RuStoreUserUnauthorizedException') {
        monetizationTypeResource.setStatus(
          MonetizationStatus.storeNotAuthorized,
        );
      } else {
        monetizationTypeResource.setStatus(MonetizationStatus.notAvailable);
      }
    }
  }

  /// Updates the state based on a purchase update.
  Future<void> handleSubscriptionUpdate(
    final PurchaseVerificationDtoModel dto,
  ) async {
    switch (dto.status) {
      case PurchaseStatus.restored:
      case PurchaseStatus.purchased:
        await _confirmPurchase(dto);
        return;
      case PurchaseStatus.error:
        // TODO(arenukvern): add error notification
        await _confirmPurchase(dto);
      case PurchaseStatus.pending:
        _state = SubscriptionManagerStatus.pending;
        notifyListeners();
        return;
      case PurchaseStatus.canceled:
        _setSubscriptionAsFree();
        return;
    }
  }

  Future<bool> subscribe(final PurchaseProductDetailsModel details) async {
    if (_state == SubscriptionManagerStatus.subscribed) return false;
    _state = SubscriptionManagerStatus.pending;
    notifyListeners();
    final result = await purchaseManager.subscribe(details);
    return _handleSubscriptionResult(result);
  }

  Future<void> cancel(final PurchaseProductDetailsModel details) async {
    final result = await purchaseManager.cancel(details.productId);
    switch (result.type) {
      case ResultType.success:
        _setSubscriptionAsFree();
      case ResultType.failure:
      // Handle failure if needed
    }
    notifyListeners();
  }

  Future<bool> _confirmPurchase(
    final PurchaseVerificationDtoModel details,
  ) async {
    if (details.status
        case PurchaseStatus.error ||
            PurchaseStatus.purchased ||
            PurchaseStatus.restored) {
      final result = await purchaseManager.completePurchase(details);
      switch (result.type) {
        case ResultType.success:
          if (details.status
              case (PurchaseStatus.purchased || PurchaseStatus.restored)) {
            final purchaseInfo = await purchaseManager.getPurchaseDetails(
              details.purchaseId,
            );
            setActiveSubscription(purchaseInfo);
            _state = SubscriptionManagerStatus.subscribed;
            notifyListeners();
            return true;
          }
        case ResultType.failure:
          // Handle failure if needed
          return false;
      }
    }
    notifyListeners();
    return false;
  }

  Future<bool> _handleSubscriptionResult(
    final PurchaseResultModel result,
  ) async {
    switch (result.type) {
      case ResultType.success:
        return _confirmPurchase(result.details!.toVerificationDto());
      case ResultType.failure:
        _setSubscriptionAsFree();
    }
    return false;
  }

  /// Checks if the user has access to premium features.
  bool hasActiveSubscription() => state == SubscriptionManagerStatus.subscribed;
}
