# xsoulspace_monetization_rustore

RuStore monetization provider implementation for the `xsoulspace_monetization_interface` contracts.

## Production readiness

- Supported platforms: Android devices with RuStore billing services.
- Known limitations:
  - Non-Android environments return `MonetizationStoreStatus.notAvailable`.
  - Cancel flow is available only for two-step purchases per RuStore API constraints.
  - Subscription management is delegated to the RuStore app deep link.
- Required configuration:
  - Set `consoleApplicationId` and `deeplinkScheme` from your RuStore console project.
  - Ensure `rustore_billing_api` integration and Android manifest setup are present in the host app.
  - Map product IDs and durations consistently with your backend verification logic.
- Rollback guidance:
  - Pin the previous stable package version in `pubspec.yaml` and redeploy.
  - Disable purchase initiation UI until rollback validation is complete.
  - Re-run purchase, restore, and cancel smoke tests after rollback.

## Installation

```yaml
dependencies:
  xsoulspace_monetization_rustore: ^1.0.0
```

## Usage

```dart
import 'package:xsoulspace_monetization_rustore/xsoulspace_monetization_rustore.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

final provider = RustorePurchaseProvider(
  consoleApplicationId: '<your_console_application_id>',
  deeplinkScheme: '<your_deeplink_scheme>',
);

final status = await provider.init();
if (status.isLoaded) {
  final products = await provider.getProductDetails([
    PurchaseProductId.fromJson('product_1'),
  ]);
  if (products.isNotEmpty) {
    await provider.purchaseNonConsumable(products.first);
  }
}
```

## License

MIT (see [LICENSE](LICENSE)).
