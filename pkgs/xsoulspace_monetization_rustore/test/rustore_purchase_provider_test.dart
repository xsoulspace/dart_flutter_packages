import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_monetization_rustore/xsoulspace_monetization_rustore.dart';

void main() {
  group('RustorePurchaseProvider', () {
    test('parses duration from product identifiers', () {
      expect(
        RustorePurchaseProvider.getDurationFromProductId(
          PurchaseProductId.fromJson('pro_month_3'),
        ),
        const Duration(days: 90),
      );

      expect(
        RustorePurchaseProvider.getDurationFromProductId(
          PurchaseProductId.fromJson('no_duration_info'),
        ),
        Duration.zero,
      );
    });

    test('returns notAvailable on unsupported platforms', () async {
      if (Platform.isAndroid) {
        return;
      }

      final provider = RustorePurchaseProvider(
        consoleApplicationId: 'console-id',
        deeplinkScheme: 'xsoulspace',
      );

      final status = await provider.init();
      await provider.dispose();

      expect(status, MonetizationStoreStatus.notAvailable);
    });
  });

  group('purchaseStatusFromRustoreState', () {
    test('one-step paid maps to purchased (regression: stuck-on-paywall)', () {
      // RuStore returns `paid` as the terminal success state for one-step
      // subscriptions. Mapping it to `pendingVerification` left users stuck
      // on the paywall because the foundation never called
      // `confirmPurchaseCommand`.
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.paid,
          purchaseType: RustorePurchaseType.oneStep,
        ),
        PurchaseStatus.purchased,
      );
    });

    test('two-step paid still requires verification', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.paid,
          purchaseType: RustorePurchaseType.twoStep,
        ),
        PurchaseStatus.pendingVerification,
      );
    });

    test('active/paused subscription states map to purchased', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.active,
          purchaseType: RustorePurchaseType.oneStep,
        ),
        PurchaseStatus.purchased,
      );
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.paused,
          purchaseType: RustorePurchaseType.oneStep,
        ),
        PurchaseStatus.purchased,
      );
    });

    test('confirmed and consumed map to purchased', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.confirmed,
          purchaseType: RustorePurchaseType.twoStep,
        ),
        PurchaseStatus.purchased,
      );
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.consumed,
          purchaseType: RustorePurchaseType.twoStep,
        ),
        PurchaseStatus.purchased,
      );
    });

    test('created/invoiceCreated stay pending', () {
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.created,
          purchaseType: RustorePurchaseType.oneStep,
        ),
        PurchaseStatus.pendingVerification,
      );
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.invoiceCreated,
          purchaseType: RustorePurchaseType.oneStep,
        ),
        PurchaseStatus.pendingVerification,
      );
    });

    test('terminal failure states map to canceled / error', () {
      for (final state in [
        RustorePurchaseStatus.cancelled,
        RustorePurchaseStatus.closed,
        RustorePurchaseStatus.terminated,
        RustorePurchaseStatus.reversed,
      ]) {
        expect(
          purchaseStatusFromRustoreState(
            state,
            purchaseType: RustorePurchaseType.oneStep,
          ),
          PurchaseStatus.canceled,
          reason: '$state should map to canceled',
        );
      }
      expect(
        purchaseStatusFromRustoreState(
          RustorePurchaseStatus.unknown,
          purchaseType: RustorePurchaseType.oneStep,
        ),
        PurchaseStatus.error,
      );
    });
  });
}
