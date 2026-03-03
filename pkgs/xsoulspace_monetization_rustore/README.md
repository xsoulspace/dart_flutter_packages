# xsoulspace_monetization_rustore

RuStore monetization provider implementation for the `xsoulspace_monetization_interface` contracts.

## Status

Early-stage package. Validate behavior in your app and store configuration before production rollout.

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
