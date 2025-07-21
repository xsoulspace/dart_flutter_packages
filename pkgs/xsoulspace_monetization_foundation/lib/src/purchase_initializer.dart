import 'dart:async';

import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'commands/commands.dart';
import 'models/models.dart';
import 'resources/resources.dart';

class PurchaseInitializer {
  PurchaseInitializer({
    required this.monetizationStatusResource,
    required this.purchaseProvider,
    required this.restorePurchasesCommand,
    required this.handlePurchaseUpdateCommand,
    required this.loadSubscriptionsCommand,
  });
  final MonetizationStatusResource monetizationStatusResource;
  final PurchaseProvider purchaseProvider;
  final RestorePurchasesCommand restorePurchasesCommand;
  final HandlePurchaseUpdateCommand handlePurchaseUpdateCommand;
  final LoadSubscriptionsCommand loadSubscriptionsCommand;

  StreamSubscription<List<PurchaseDetailsModel>>? _purchaseUpdateSubscription;
  Future<void> restore() => restorePurchasesCommand.execute();

  Future<void> init() async {
    monetizationStatusResource.setStatus(MonetizationStatus.loading);
    final isInitialized = await purchaseProvider.init();

    monetizationStatusResource.setStatus(
      isInitialized
          ? MonetizationStatus.loaded
          : MonetizationStatus.notAvailable,
    );
    if (!isInitialized) return;

    await loadSubscriptionsCommand.execute();
    await _restoreAndListen();
  }

  Future<void> _restoreAndListen() async {
    await restorePurchasesCommand.execute();
    await _purchaseUpdateSubscription?.cancel();
    _purchaseUpdateSubscription = purchaseProvider.purchaseStream.listen(
      _handlePurchaseUpdate,
    );
  }

  Future<void> _handlePurchaseUpdate(
    final List<PurchaseDetailsModel> purchases,
  ) async {
    for (final purchase in purchases) {
      await handlePurchaseUpdateCommand.execute(purchase.toVerificationDto());
    }
  }

  Future<void> dispose() async {
    await _purchaseUpdateSubscription?.cancel();
  }
}
