import 'package:flutter_test/flutter_test.dart';
// ignore_for_file: unused_import
import 'package:xsoulspace_monetization_foundation/xsoulspace_monetization_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

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
  });
}
