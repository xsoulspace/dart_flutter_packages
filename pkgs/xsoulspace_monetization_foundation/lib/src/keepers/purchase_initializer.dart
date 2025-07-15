import 'dart:async';

import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../purchases/purchase_manager.dart';
import 'subscription_manager.dart';

class PurchaseInitializer {
  PurchaseInitializer({
    required this.monetizationTypeResource,
    required this.subscriptionManager,
    required this.purchaseManager,
  });
  final MonetizationStatusResource monetizationTypeResource;
  final PurchaseManager purchaseManager;
  final SubscriptionManager subscriptionManager;

  StreamSubscription<List<PurchaseDetailsModel>>? _purchaseUpdateSubscription;
  Future<void> restore() => _restore();

  Future<void> init() async {
    monetizationTypeResource.setStatus(MonetizationStatus.loading);
    final isInitialized = await purchaseManager.init();

    monetizationTypeResource.setStatus(
      isInitialized
          ? MonetizationStatus.loaded
          : MonetizationStatus.notAvailable,
    );
    if (!isInitialized) return;

    await _restoreAndListen();
  }

  Future<void> _restoreAndListen() async {
    await _restore();
    await _purchaseUpdateSubscription?.cancel();
    _purchaseUpdateSubscription = purchaseManager.purchaseStream.listen(
      _handlePurchaseUpdate,
    );
  }

  Future<void> _restore() async {
    final result = await purchaseManager.restorePurchases();
    switch (result.type) {
      case ResultType.success:
        for (final purchase in result.restoredPurchases) {
          if (!purchase.isActive) continue;
          await subscriptionManager.handleSubscriptionUpdate(
            purchase.toVerificationDto(),
          );
        }
      case ResultType.failure:
        // Handle failure if needed
        break;
    }
  }

  Future<void> _handlePurchaseUpdate(
    final List<PurchaseDetailsModel> purchases,
  ) async {
    for (final purchase in purchases) {
      await subscriptionManager.handleSubscriptionUpdate(
        purchase.toVerificationDto(),
      );
    }
  }

  Future<void> dispose() async {
    await _purchaseUpdateSubscription?.cancel();
  }
}
