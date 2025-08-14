import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: unused_import
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'support/builders.dart';
import 'support/harness.dart';

void main() {
  late MonetizationTestEnv env;

  setUp(() => env = MonetizationTestEnv()..setUp());
  tearDown(() => env.tearDown());

  group('MonetizationFoundation', () {
    test(
      'init sets status and loads/restore when loaded/authorized/installed',
      () async {
        final foundation = env.makeFoundation();
        await foundation.init(productIds: [PurchaseProductId.fromJson('p')]);
        expect(env.monetizationStatus.status, MonetizationStoreStatus.loaded);
      },
    );

    test('dispose cancels provider', () async {
      final foundation = env.makeFoundation();
      await foundation.init(productIds: []);
      await foundation.dispose();
    });

    test('initLocal updates status from local without waiting init', () async {
      final foundation = env.makeFoundation();
      // Save active locally
      await env.purchasesLocalApi.saveActiveSubscription(
        aPurchase(active: true),
      );

      // Call initLocal first
      await foundation.initLocal();
      expect(env.subscriptionStatus.isSubscribed, true);

      // Ensure init awaits initLocal (should already be completed)
      await foundation.init(productIds: [PurchaseProductId.fromJson('p')]);
      expect(env.monetizationStatus.status, MonetizationStoreStatus.loaded);
    });
  });
}
