import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import '../support/builders.dart';
import '../support/harness.dart';
import '../support/matchers.dart';

void main() {
  group('RestoreLocalPurchasesCommand', () {
    late MonetizationTestEnv env;

    setUp(() => env = MonetizationTestEnv()..setUp());
    tearDown(() => env.tearDown());

    // Data-driven test cases for different purchase statuses

    <
          String,
          ({
            PurchaseDetailsModel Function() purchase,
            bool expectedResult,
            Matcher statusMatcher,
          })
        >{
          'active purchased subscription': (
            purchase: () => aPurchase(active: true),
            expectedResult: true,
            statusMatcher: isSubscribed(),
          ),
          'pending confirmation subscription': (
            purchase: () => aPurchase(pendingConfirmation: true),
            expectedResult: false,
            statusMatcher: isPendingConfirmationStatus(),
          ),
          'inactive purchased subscription': (
            purchase: aPurchase,
            expectedResult: false,
            statusMatcher: isFreeStatus(),
          ),
          'pending subscription': (
            purchase: () => aPurchase(pending: true),
            expectedResult: false,
            statusMatcher: isFreeStatus(),
          ),
          'canceled subscription': (
            purchase: () => aPurchase(cancelled: true),
            expectedResult: false,
            statusMatcher: isFreeStatus(),
          ),
          'error status subscription': (
            purchase: () => PurchaseDetailsModel(
              purchaseDate: DateTime.now(),
              status: PurchaseStatus.error,
            ),
            expectedResult: false,
            statusMatcher: isFreeStatus(),
          ),
          'empty purchase': (
            purchase: () => PurchaseDetailsModel.empty,
            expectedResult: false,
            statusMatcher: isFreeStatus(),
          ),
        }
        .forEach((final name, final testCase) {
          test(name, () async {
            await env.givenLocalActiveSubscription(testCase.purchase());
            final cmd = env.makeRestoreLocalPurchasesCommand();

            final result = await cmd.execute();

            expect(result, testCase.expectedResult);
            expect(env.subscriptionStatus, testCase.statusMatcher);
          });
        });

    test('active consumable purchase sets subscribed status', () async {
      final activeConsumable = PurchaseDetailsModel(
        purchaseDate: DateTime.now(),
        status: PurchaseStatus.purchased,
      );
      await env.givenLocalActiveSubscription(activeConsumable);
      final cmd = env.makeRestoreLocalPurchasesCommand();

      final result = await cmd.execute();

      expect(result, isTrue);
      expect(env.subscriptionStatus, isSubscribed());
    });

    test(
      'pending confirmation with active expiry sets pending status',
      () async {
        final pendingActiveSubscription = PurchaseDetailsModel(
          purchaseDate: DateTime.now(),
          status: PurchaseStatus.pendingConfirmation,
          purchaseType: PurchaseProductType.subscription,
          expiryDate: DateTime.now().add(const Duration(days: 30)),
        );
        await env.givenLocalActiveSubscription(pendingActiveSubscription);
        final cmd = env.makeRestoreLocalPurchasesCommand();

        final result = await cmd.execute();

        expect(result, isFalse);
        expect(env.subscriptionStatus, isPendingConfirmationStatus());
      },
    );
  });
}
