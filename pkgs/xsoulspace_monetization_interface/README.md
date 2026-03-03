# xsoulspace_monetization_interface

Common contracts and models for monetization providers used by xsoulspace packages.

## What is inside

- `PurchaseProvider` abstraction for store adapters
- Unified purchase/product models
- Store status and operation result types

## Installation

```yaml
dependencies:
  xsoulspace_monetization_interface: ^0.8.2
```

## Usage

```dart
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

Future<void> initProvider(PurchaseProvider provider) async {
  final status = await provider.init();
  if (status != MonetizationStoreStatus.loaded) {
    return;
  }

  provider.purchaseStream.listen((events) {
    for (final purchase in events) {
      // Verify and deliver content.
      print(purchase.productId.value);
    }
  });
}
```

## License

MIT (see [LICENSE](LICENSE)).
