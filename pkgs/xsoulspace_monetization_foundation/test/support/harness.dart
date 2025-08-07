import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'builders.dart';
import 'fakes.dart';

/// Centralized test environment for wiring shared resources, provider and
/// command factories. Keeps tests short and intent-focused.
class MonetizationTestEnv {
  MonetizationTestEnv();

  // Shared fakes
  late FakeProvider provider;
  late FakeLocalDb localDb;
  late PurchasesLocalApi purchasesLocalApi;

  // Shared resources
  late MonetizationStoreStatusResource monetizationStatus;
  late MonetizationTypeResource monetizationType;
  late ActiveSubscriptionResource activeSubscription;
  late SubscriptionStatusResource subscriptionStatus;
  late AvailableSubscriptionsResource availableSubscriptions;
  late PaywallSelectedSubscriptionResource paywallSelectedSubscription;
  late PurchasePaywallErrorResource purchasePaywallError;

  /// Initialize fresh environment
  void setUp() {
    provider = FakeProvider();
    localDb = FakeLocalDb();
    purchasesLocalApi = PurchasesLocalApi(localDb: localDb);

    monetizationStatus = MonetizationStoreStatusResource();
    monetizationType = MonetizationTypeResource(MonetizationType.subscription);
    activeSubscription = ActiveSubscriptionResource();
    subscriptionStatus = SubscriptionStatusResource();
    availableSubscriptions = AvailableSubscriptionsResource();
    paywallSelectedSubscription = PaywallSelectedSubscriptionResource();
    purchasePaywallError = PurchasePaywallErrorResource();
  }

  Future<void> tearDown() async {
    await provider.dispose();
  }

  // ---------- Configuration (Given) helpers ----------

  /// Configure provider to return subscribe success.
  void givenSubscribeSuccess({
    final bool shouldConfirm = true,
    final PurchaseDetailsModel? details,
  }) {
    provider = FakeProvider(
      subscribeResult: PurchaseResultModel.success(
        details ?? aPurchase(pendingConfirmation: true),
        shouldConfirmPurchase: shouldConfirm,
      ),
    );
  }

  /// Configure provider to return subscribe failure.
  void givenSubscribeFailure({
    final String error = 'err',
    final PurchaseDetailsModel? details,
  }) {
    provider = FakeProvider(
      subscribeResult: PurchaseResultModel(
        details: details ?? aPurchase(),
        type: ResultType.failure,
        error: error,
      ),
    );
  }

  /// Configure provider to return complete success.
  void givenCompleteSuccess() {
    provider = FakeProvider(
      completeResult: CompletePurchaseResultModel.success(),
    );
  }

  /// Configure provider to return complete failure with [error].
  void givenCompleteFailure([final String error = 'err']) {
    provider = FakeProvider(
      completeResult: CompletePurchaseResultModel.failure(error),
    );
  }

  /// Configure provider to return restore failure with [error].
  void givenRestoreFailure([final String error = 'err']) {
    provider = FakeProvider(restoreResult: RestoreResultModel.failure(error));
  }

  /// Configure provider to return restore success with [purchases].
  void givenRestoreSuccess([
    final List<PurchaseDetailsModel> purchases = const [],
  ]) {
    provider = FakeProvider(
      restoreResult: RestoreResultModel.success(purchases),
    );
  }

  /// Configure provider with available [products].
  void withSubscriptions(final List<PurchaseProductDetailsModel> products) {
    provider = FakeProvider(subscriptions: products);
  }

  // ---------- Command factories (use shared resources/provider) ----------

  ConfirmPurchaseCommand makeConfirmPurchaseCommand() => ConfirmPurchaseCommand(
    purchaseProvider: provider,
    activeSubscriptionResource: activeSubscription,
    subscriptionStatusResource: subscriptionStatus,
    purchasePaywallErrorResource: purchasePaywallError,
  );

  HandlePurchaseUpdateCommand makeHandlePurchaseUpdateCommand() =>
      HandlePurchaseUpdateCommand(
        confirmPurchaseCommand: makeConfirmPurchaseCommand(),
        subscriptionStatusResource: subscriptionStatus,
        activeSubscriptionResource: activeSubscription,
        purchasesLocalApi: purchasesLocalApi,
      );

  RestorePurchasesCommand _makeRestorePurchasesCommand() =>
      RestorePurchasesCommand(
        purchaseProvider: provider,
        purchasesLocalApi: purchasesLocalApi,
        handlePurchaseUpdateCommand: makeHandlePurchaseUpdateCommand(),
        subscriptionStatusResource: subscriptionStatus,
      );

  CancelSubscriptionCommand makeCancelSubscriptionCommand() =>
      CancelSubscriptionCommand(
        purchaseProvider: provider,
        activeSubscriptionResource: activeSubscription,
        subscriptionStatusResource: subscriptionStatus,
        restorePurchasesCommand: _makeRestorePurchasesCommand(),
      );

  /// Expose restore purchases command.
  RestorePurchasesCommand makeRestorePurchasesCommand() =>
      RestorePurchasesCommand(
        purchaseProvider: provider,
        purchasesLocalApi: purchasesLocalApi,
        handlePurchaseUpdateCommand: makeHandlePurchaseUpdateCommand(),
        subscriptionStatusResource: subscriptionStatus,
      );

  SubscribeCommand makeSubscribeCommand() => SubscribeCommand(
    purchaseProvider: provider,
    subscriptionStatusResource: subscriptionStatus,
    confirmPurchaseCommand: makeConfirmPurchaseCommand(),
    cancelSubscriptionCommand: makeCancelSubscriptionCommand(),
    purchasePaywallErrorResource: purchasePaywallError,
  );

  LoadSubscriptionsCommand makeLoadSubscriptionsCommand({
    required final List<PurchaseProductId> productIds,
  }) => LoadSubscriptionsCommand(
    purchaseProvider: provider,
    monetizationStatusResource: monetizationStatus,
    availableSubscriptionsResource: availableSubscriptions,
    productIds: productIds,
  );

  /// Convenience accessor for the named resources record used by
  /// [MonetizationFoundation].
  ({
    MonetizationStoreStatusResource status,
    MonetizationTypeResource type,
    ActiveSubscriptionResource activeSubscription,
    SubscriptionStatusResource subscriptionStatus,
    AvailableSubscriptionsResource availableSubscriptions,
    PaywallSelectedSubscriptionResource paywallSelectedSubscription,
    PurchasePaywallErrorResource purchasePaywallError,
  })
  get resourcesRecord => (
    status: monetizationStatus,
    type: monetizationType,
    activeSubscription: activeSubscription,
    subscriptionStatus: subscriptionStatus,
    availableSubscriptions: availableSubscriptions,
    paywallSelectedSubscription: paywallSelectedSubscription,
    purchasePaywallError: purchasePaywallError,
  );

  /// Build a foundation instance using the current env.
  MonetizationFoundation makeFoundation() => MonetizationFoundation(
    resources: resourcesRecord,
    purchaseProvider: provider,
    purchasesLocalApi: purchasesLocalApi,
  );
}
