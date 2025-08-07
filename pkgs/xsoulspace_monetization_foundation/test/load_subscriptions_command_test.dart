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

  group('LoadSubscriptionsCommand', () {
    test('loads subscriptions into resource', () async {
      env.withSubscriptions([
        aProduct(id: PurchaseProductId.fromJson('prod'), name: 'Premium'),
      ]);
      final cmd = env.makeLoadSubscriptionsCommand(
        productIds: [PurchaseProductId.fromJson('prod')],
      );
      await cmd.execute();
      expect(env.availableSubscriptions.subscriptions.isLoaded, isTrue);
      expect(
        env.availableSubscriptions
            .getSubscription(PurchaseProductId.fromJson('prod'))
            ?.name,
        'Premium',
      );
    });
  });
}
