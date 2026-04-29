import 'package:flutter_test/flutter_test.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_monetization_rustore/xsoulspace_monetization_rustore.dart';

void main() {
  group('purchaseStatusFromRustoreState', () {
    test(
      'subscription paid maps to purchased (regression: stuck-on-paywall)',
      () {
        // RuStore reports `paid` as the terminal success state for
        // subscriptions / non-consumables. Previously this was bucketed as
        // `pendingVerification`, which left the foundation's
        // `confirmPurchaseCommand` failing the `isPurchased` check — users
        // were stuck on the paywall after a successful purchase.
        expect(
          purchaseStatusFromRustoreState(
            RustorePurchaseState.paid,
            productType: PurchaseProductType.subscription,
          ),
          PurchaseStatus.purchased,
        );
      },
    );

    test('non-consumable paid maps to purchased', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseState.paid,
          productType: PurchaseProductType.nonConsumable,
        ),
        PurchaseStatus.purchased,
      );
    });

    test('consumable paid still requires confirmation', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseState.paid,
          productType: PurchaseProductType.consumable,
        ),
        PurchaseStatus.pendingVerification,
      );
    });

    test('confirmed and consumed always map to purchased', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseState.confirmed,
          productType: PurchaseProductType.consumable,
        ),
        PurchaseStatus.purchased,
      );
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseState.consumed,
          productType: PurchaseProductType.consumable,
        ),
        PurchaseStatus.purchased,
      );
    });

    test('paused subscription stays purchased', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseState.paused,
          productType: PurchaseProductType.subscription,
        ),
        PurchaseStatus.purchased,
      );
    });

    test('created/invoiceCreated stay pending', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseState.created,
          productType: PurchaseProductType.subscription,
        ),
        PurchaseStatus.pendingVerification,
      );
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseState.invoiceCreated,
          productType: PurchaseProductType.subscription,
        ),
        PurchaseStatus.pendingVerification,
      );
    });

    test('terminal failure states map to canceled', () {
      for (final state in [
        RustorePurchaseState.cancelled,
        RustorePurchaseState.closed,
        RustorePurchaseState.terminated,
      ]) {
        expect(
          purchaseStatusFromRustoreState(
            state,
            productType: PurchaseProductType.subscription,
          ),
          PurchaseStatus.canceled,
          reason: '$state should map to canceled',
        );
      }
    });

    test('null state stays pending', () {
      expect(
        purchaseStatusFromRustoreState(
          null,
          productType: PurchaseProductType.subscription,
        ),
        PurchaseStatus.pendingVerification,
      );
    });
  });
}
