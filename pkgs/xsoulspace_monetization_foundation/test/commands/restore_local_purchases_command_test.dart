import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../support/builders.dart';

/// Fake implementation of PurchasesLocalApi that records calls and values
class FakePurchasesLocalApi {
  FakePurchasesLocalApi();

  PurchaseDetailsModel _activeSubscription = PurchaseDetailsModel.empty;
  int _getActiveSubscriptionCalls = 0;
  int _clearActiveSubscriptionCalls = 0;

  /// Configure the active subscription to return
  void givenActiveSubscription(PurchaseDetailsModel subscription) {
    _activeSubscription = subscription;
  }

  /// Get the number of times getActiveSubscription was called
  int get getActiveSubscriptionCalls => _getActiveSubscriptionCalls;

  /// Get the number of times clearActiveSubscription was called
  int get clearActiveSubscriptionCalls => _clearActiveSubscriptionCalls;

  /// Reset all call counters
  void reset() {
    _getActiveSubscriptionCalls = 0;
    _clearActiveSubscriptionCalls = 0;
  }

  Future<PurchaseDetailsModel> getActiveSubscription() async {
    _getActiveSubscriptionCalls++;
    return _activeSubscription;
  }

  Future<void> clearActiveSubscription() async {
    _clearActiveSubscriptionCalls++;
  }
}

/// Fake implementation of SubscriptionStatusResource that records calls
class FakeSubscriptionStatusResource {
  FakeSubscriptionStatusResource();

  SubscriptionStatus _status = SubscriptionStatus.free;
  final List<SubscriptionStatus> _setCalls = [];

  /// Get the current status
  SubscriptionStatus get status => _status;

  /// Get all set() calls in order
  List<SubscriptionStatus> get setCalls => List.unmodifiable(_setCalls);

  /// Reset all recorded calls
  void reset() {
    _setCalls.clear();
  }

  void set(SubscriptionStatus status) {
    _status = status;
    _setCalls.add(status);
  }

  bool get isFree => status == SubscriptionStatus.free;
  bool get isSubscribed => status == SubscriptionStatus.subscribed;
  bool get isPendingConfirmation => status == SubscriptionStatus.pendingPaymentConfirmation;
}

void main() {
  late FakePurchasesLocalApi fakeLocalApi;
  late FakeSubscriptionStatusResource fakeSubscriptionStatus;
  late RestoreLocalPurchasesCommand command;

  setUp(() {
    fakeLocalApi = FakePurchasesLocalApi();
    fakeSubscriptionStatus = FakeSubscriptionStatusResource();
    command = RestoreLocalPurchasesCommand(
      purchasesLocalApi: fakeLocalApi,
      subscriptionStatusResource: fakeSubscriptionStatus,
    );
  });

  tearDown(() {
    fakeLocalApi.reset();
    fakeSubscriptionStatus.reset();
  });

  group('RestoreLocalPurchasesCommand', () {
    test(
      'PurchaseStatus.purchased with isActive==true: sets subscribed, does not clear, returns true',
      () async {
        // Arrange
        final activePurchase = aPurchase(active: true);
        fakeLocalApi.givenActiveSubscription(activePurchase);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isTrue);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.subscribed);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.subscribed]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 0);
      },
    );

    test(
      'PurchaseStatus.pendingConfirmation: sets pendingPaymentConfirmation, clears, returns false',
      () async {
        // Arrange
        final pendingPurchase = aPurchase(pendingConfirmation: true);
        fakeLocalApi.givenActiveSubscription(pendingPurchase);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.pendingPaymentConfirmation);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.pendingPaymentConfirmation]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 1);
      },
    );

    test(
      'PurchaseStatus.purchased with isActive==false: sets free, clears, returns false',
      () async {
        // Arrange
        final inactivePurchase = aPurchase(active: false);
        fakeLocalApi.givenActiveSubscription(inactivePurchase);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.free);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.free]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 1);
      },
    );

    test(
      'PurchaseStatus.pending: sets free, clears, returns false',
      () async {
        // Arrange
        final pendingPurchase = aPurchase(pending: true);
        fakeLocalApi.givenActiveSubscription(pendingPurchase);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.free);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.free]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 1);
      },
    );

    test(
      'PurchaseStatus.canceled: sets free, clears, returns false',
      () async {
        // Arrange
        final canceledPurchase = aPurchase(cancelled: true);
        fakeLocalApi.givenActiveSubscription(canceledPurchase);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.free);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.free]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 1);
      },
    );

    test(
      'PurchaseStatus.error: sets free, clears, returns false',
      () async {
        // Arrange
        final errorPurchase = PurchaseDetailsModel(
          purchaseDate: DateTime.now(),
          status: PurchaseStatus.error,
        );
        fakeLocalApi.givenActiveSubscription(errorPurchase);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.free);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.free]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 1);
      },
    );

    test(
      'empty purchase (default): sets free, clears, returns false',
      () async {
        // Arrange
        fakeLocalApi.givenActiveSubscription(PurchaseDetailsModel.empty);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.free);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.free]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 1);
      },
    );

    test(
      'consumable purchase with purchased status and active: sets subscribed, does not clear, returns true',
      () async {
        // Arrange
        final activeConsumable = PurchaseDetailsModel(
          purchaseDate: DateTime.now(),
          status: PurchaseStatus.purchased,
          purchaseType: PurchaseProductType.consumable,
        );
        fakeLocalApi.givenActiveSubscription(activeConsumable);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isTrue);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.subscribed);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.subscribed]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 0);
      },
    );

    test(
      'subscription with pendingConfirmation and active: sets pendingPaymentConfirmation, clears, returns false',
      () async {
        // Arrange
        final pendingActiveSubscription = PurchaseDetailsModel(
          purchaseDate: DateTime.now(),
          status: PurchaseStatus.pendingConfirmation,
          purchaseType: PurchaseProductType.subscription,
          expiryDate: DateTime.now().add(const Duration(days: 30)),
        );
        fakeLocalApi.givenActiveSubscription(pendingActiveSubscription);

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(fakeSubscriptionStatus.status, SubscriptionStatus.pendingPaymentConfirmation);
        expect(fakeSubscriptionStatus.setCalls, [SubscriptionStatus.pendingPaymentConfirmation]);
        expect(fakeLocalApi.getActiveSubscriptionCalls, 1);
        expect(fakeLocalApi.clearActiveSubscriptionCalls, 1);
      },
    );
  });
}
