import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../models/models.dart';
import '../resources/resources.dart';

@immutable
class LoadSubscriptionsCommand {
  const LoadSubscriptionsCommand({
    required this.purchaseProvider,
    required this.monetizationStatusResource,
    required this.availableSubscriptionsResource,
    required this.productIds,
  });
  final List<PurchaseProductId> productIds;
  final PurchaseProvider purchaseProvider;
  final MonetizationStatusResource monetizationStatusResource;
  final AvailableSubscriptionsResource availableSubscriptionsResource;

  Future<void> execute() async {
    try {
      final subscriptions = await purchaseProvider.getSubscriptions(productIds);
      availableSubscriptionsResource.set(
        LoadableContainer.loaded(subscriptions),
      );
    } on PlatformException catch (e, stackTrace) {
      debugPrint('Failed to get subscriptions: $e $stackTrace');
      if (e.code == 'RuStoreUserUnauthorizedException') {
        monetizationStatusResource.setStatus(
          MonetizationStatus.storeNotAuthorized,
        );
      } else {
        monetizationStatusResource.setStatus(MonetizationStatus.notAvailable);
      }
    }
  }
}
