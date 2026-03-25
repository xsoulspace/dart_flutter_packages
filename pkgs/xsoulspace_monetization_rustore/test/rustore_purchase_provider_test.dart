import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
