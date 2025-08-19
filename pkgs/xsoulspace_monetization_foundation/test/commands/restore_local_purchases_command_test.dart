import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../support/builders.dart';
import '../support/harness.dart';

void main() {
  late MonetizationTestEnv env;

  setUp(() => env = MonetizationTestEnv()..setUp());
  tearDown(() => env.tearDown());

  group('RestoreLocalPurchasesCommand', () {
    test(
      'PurchaseStatus.purchased with isActive==true: sets subscribed, does not clear, returns true',
      () async {
        // Arrange
        final activePurchase = aPurchase(active: true);
        await env.givenLocalActiveSubscription(activePurchase);
        final command = env.makeRestoreLocalPurchasesCommand();

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isTrue);
        expect(env.subscriptionStatus.status, SubscriptionStatus.subscribed);
        expect(env.subscriptionStatus.setCalls, 1);
      },
    );

    test(
      'PurchaseStatus.pendingConfirmation: sets pendingPaymentConfirmation, clears, returns false',
      () async {
        // Arrange
        final pendingPurchase = aPurchase(pendingConfirmation: true);
        await env.givenLocalActiveSubscription(pendingPurchase);
        final command = env.makeRestoreLocalPurchasesCommand();

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(
          env.subscriptionStatus.status,
          SubscriptionStatus.pendingPaymentConfirmation,
        );
        expect(env.subscriptionStatus.setCalls, [
          SubscriptionStatus.pendingPaymentConfirmation,
        ]);
      },
    );

    test(
      'PurchaseStatus.purchased with isActive==false: sets free, clears, returns false',
      () async {
        // Arrange
        final inactivePurchase = aPurchase();
        await env.givenLocalActiveSubscription(inactivePurchase);
        final command = env.makeRestoreLocalPurchasesCommand();

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(env.subscriptionStatus.status, SubscriptionStatus.free);
        expect(env.subscriptionStatus.setCalls, [SubscriptionStatus.free]);
      },
    );

    test('PurchaseStatus.pending: sets free, clears, returns false', () async {
      // Arrange
      final pendingPurchase = aPurchase(pending: true);
      await env.givenLocalActiveSubscription(pendingPurchase);
      final command = env.makeRestoreLocalPurchasesCommand();

      // Act
      final result = await command.execute();

      // Assert
      expect(result, isFalse);
      expect(env.subscriptionStatus.status, SubscriptionStatus.free);
      expect(env.subscriptionStatus.setCalls, [SubscriptionStatus.free]);
    });

    test('PurchaseStatus.canceled: sets free, clears, returns false', () async {
      // Arrange
      final canceledPurchase = aPurchase(cancelled: true);
      await env.givenLocalActiveSubscription(canceledPurchase);
      final command = env.makeRestoreLocalPurchasesCommand();

      // Act
      final result = await command.execute();

      // Assert
      expect(result, isFalse);
      expect(env.subscriptionStatus.status, SubscriptionStatus.free);
      expect(env.subscriptionStatus.setCalls, [SubscriptionStatus.free]);
    });

    test('PurchaseStatus.error: sets free, clears, returns false', () async {
      // Arrange
      final errorPurchase = PurchaseDetailsModel(
        purchaseDate: DateTime.now(),
        status: PurchaseStatus.error,
      );
      await env.givenLocalActiveSubscription(errorPurchase);
      final command = env.makeRestoreLocalPurchasesCommand();

      // Act
      final result = await command.execute();

      // Assert
      expect(result, isFalse);
      expect(env.subscriptionStatus.status, SubscriptionStatus.free);
      expect(env.subscriptionStatus.setCalls, [SubscriptionStatus.free]);
    });

    test(
      'empty purchase (default): sets free, clears, returns false',
      () async {
        // Arrange
        await env.givenLocalActiveSubscription(PurchaseDetailsModel.empty);
        final command = env.makeRestoreLocalPurchasesCommand();

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(env.subscriptionStatus.status, SubscriptionStatus.free);
        expect(env.subscriptionStatus.setCalls, [SubscriptionStatus.free]);
      },
    );

    test(
      'consumable purchase with purchased status and active: sets subscribed, does not clear, returns true',
      () async {
        // Arrange
        final activeConsumable = PurchaseDetailsModel(
          purchaseDate: DateTime.now(),
          status: PurchaseStatus.purchased,
        );
        await env.givenLocalActiveSubscription(activeConsumable);
        final command = env.makeRestoreLocalPurchasesCommand();

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isTrue);
        expect(env.subscriptionStatus.status, SubscriptionStatus.subscribed);
        expect(env.subscriptionStatus.setCalls, [
          SubscriptionStatus.subscribed,
        ]);
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
        await env.givenLocalActiveSubscription(pendingActiveSubscription);
        final command = env.makeRestoreLocalPurchasesCommand();

        // Act
        final result = await command.execute();

        // Assert
        expect(result, isFalse);
        expect(
          env.subscriptionStatus.status,
          SubscriptionStatus.pendingPaymentConfirmation,
        );
        expect(env.subscriptionStatus.setCalls, [
          SubscriptionStatus.pendingPaymentConfirmation,
        ]);
      },
    );
  });
}
