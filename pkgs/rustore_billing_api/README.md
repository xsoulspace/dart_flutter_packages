# RuStore Billing API

A Flutter plugin for integrating RuStore billing functionality into your Flutter applications. This plugin provides a comprehensive API for managing products, handling purchases, and processing payments through the RuStore platform.

## Features

- ✅ Initialize RuStore billing client
- ✅ Retrieve available products
- ✅ Handle purchase flows
- ✅ Confirm and manage purchases
- ✅ Process deep link payments
- ✅ Stream-based event handling
- ✅ Comprehensive error handling
- ✅ Full RuStore SDK 9.1.0 support

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  rustore_billing_api: ^0.1.0
```

## Android Setup

### 1. Add RuStore Repository

In your `android/build.gradle` file, add the RuStore repository:

```gradle
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url "https://artifactory-external.vkpartner.ru/artifactory/vkid-sdk-andorid/" }
    }
}
```

### 2. Configure Deep Links

Add the following to your `android/app/src/main/AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop"
    android:theme="@style/LaunchTheme">

    <!-- Existing intent filters -->

    <!-- RuStore deep link -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="your_deeplink_scheme" />
    </intent-filter>
</activity>
```

### 3. Handle Deep Links in MainActivity

Update your `MainActivity.kt` to handle deep links:

```kotlin
class MainActivity : FlutterActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The plugin will automatically handle the intent
    }
}
```

## Usage

### Basic Setup

```dart
import 'package:rustore_billing_api/rustore_billing_api.dart';

// Register the Android implementation (call this in main() on Android)
if (Platform.isAndroid) {
  registerWith();
}

// Get the billing client instance
final billingClient = RustoreBillingClient.instance;

// Initialize the client
await billingClient.initialize(
  RustoreBillingConfig(
    consoleApplicationId: 'your_app_id_from_rustore_console',
    deeplinkScheme: 'your_deeplink_scheme',
    debugLogs: true, // Enable for development
  ),
);
```

### Listen to Events

```dart
// Listen to purchase results
billingClient.purchaseResults.listen((result) {
  switch (result.resultType) {
    case RustorePaymentResultType.success:
      print('Purchase successful: ${result.purchaseId}');
      // Confirm the purchase
      await billingClient.confirmPurchase(result.purchaseId!);
      break;
    case RustorePaymentResultType.cancelled:
      print('Purchase cancelled');
      break;
    case RustorePaymentResultType.failure:
      print('Purchase failed: ${result.errorMessage}');
      break;
  }
});

// Listen to errors
billingClient.errors.listen((error) {
  print('Billing error: ${error.message}');
});
```

### Get Products

```dart
final productIds = ['product1', 'product2', 'premium_subscription'];
final products = await billingClient.getProducts(productIds);

for (final product in products) {
  print('Product: ${product.title} - ${product.priceLabel}');
}
```

### Purchase a Product

```dart
try {
  final result = await billingClient.purchaseProduct(
    'product_id',
    developerPayload: 'optional_payload_for_verification',
  );

  if (result.resultType == RustorePaymentResultType.success) {
    // Purchase initiated successfully
    // The actual result will come through the purchaseResults stream
  }
} catch (e) {
  print('Purchase failed: $e');
}
```

### Confirm Purchase

```dart
// After receiving a successful purchase result
await billingClient.confirmPurchase(
  purchaseId,
  developerPayload: 'optional_payload',
);
```

### Get Existing Purchases

```dart
final purchases = await billingClient.getPurchases();

for (final purchase in purchases) {
  print('Purchase: ${purchase.productId} - ${purchase.purchaseState}');

  // Auto-confirm paid purchases
  if (purchase.purchaseState == RustorePurchaseState.paid) {
    await billingClient.confirmPurchase(purchase.purchaseId!);
  }
}
```

### Complete Example

```dart
import 'dart:io';
import 'package:rustore_billing_api/rustore_billing_api.dart';

class BillingService {
  final _billingClient = RustoreBillingClient.instance;
  bool _initialized = false;

    Future<void> initialize() async {
    if (_initialized) return;

    // Register Android implementation
    if (Platform.isAndroid) {
      registerWith();
    }

    // Set up listeners
    _billingClient.purchaseResults.listen(_handlePurchaseResult);
    _billingClient.errors.listen(_handleError);

    // Initialize
    await _billingClient.initialize(
      RustoreBillingConfig(
        consoleApplicationId: 'your_app_id',
        deeplinkScheme: 'your_scheme',
        debugLogs: false,
      ),
    );

    _initialized = true;

    // Process any existing purchases
    await _processExistingPurchases();
  }

  Future<void> _processExistingPurchases() async {
    final purchases = await _billingClient.getPurchases();

    for (final purchase in purchases) {
      if (purchase.purchaseState == RustorePurchaseState.paid) {
        // Deliver the product to the user
        await _deliverProduct(purchase.productId!);
        // Confirm the purchase
        await _billingClient.confirmPurchase(purchase.purchaseId!);
      }
    }
  }

  void _handlePurchaseResult(RustorePaymentResult result) async {
    if (result.resultType == RustorePaymentResultType.success) {
      // Deliver the product
      await _deliverProduct(result.purchaseId!);
      // Confirm the purchase
      await _billingClient.confirmPurchase(result.purchaseId!);
    }
  }

  void _handleError(RustoreError error) {
    print('Billing error: ${error.message}');
  }

  Future<void> _deliverProduct(String productId) async {
    // Implement your product delivery logic here
    print('Delivering product: $productId');
  }

  void dispose() {
    _billingClient.dispose();
  }
}
```

## API Reference

### RustoreBillingClient

The main client for RuStore billing operations.

#### Methods

- `initialize(RustoreBillingConfig config)` - Initialize the billing client
- `getProducts(List<String> productIds)` - Get available products
- `getPurchases()` - Get existing purchases
- `purchaseProduct(String productId, {String? developerPayload})` - Start purchase flow
- `confirmPurchase(String purchaseId, {String? developerPayload})` - Confirm purchase
- `deletePurchase(String purchaseId)` - Delete purchase
- `onNewIntent(String? intentData)` - Handle deep link intents
- `dispose()` - Clean up resources

#### Streams

- `purchaseResults` - Stream of purchase results
- `errors` - Stream of billing errors

### Models

#### RustoreBillingConfig

Configuration for the billing client.

#### RustoreProduct

Represents a product available for purchase.

#### RustorePurchase

Represents a user's purchase.

#### RustorePaymentResult

Result of a payment operation.

#### RustoreError

Error information from billing operations.

## Error Handling

The plugin provides comprehensive error handling through:

1. **Exceptions**: Synchronous operations throw `RustoreBillingException`
2. **Error Stream**: Asynchronous errors are emitted through `billingClient.errors`
3. **Result Types**: Payment results include error information

```dart
try {
  await billingClient.getProducts(['product1']);
} on RustoreBillingException catch (e) {
  print('Billing error: ${e.message}');
}
```

## Testing

Run the example app to test the integration:

```bash
cd example
flutter run
```

## Troubleshooting

### Common Issues

1. **Initialization fails**: Check your app ID and deep link scheme
2. **Products not loading**: Verify product IDs in RuStore console
3. **Purchase fails**: Ensure proper deep link configuration
4. **Deep links not working**: Check AndroidManifest.xml configuration

### Debug Mode

Enable debug logs during development:

```dart
RustoreBillingConfig(
  // ... other config
  debugLogs: true,
)
```

## Requirements

- Flutter >=3.0.0
- Android API level 21+
- RuStore app installed on device

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests to our repository.

## Support

For support and questions:

- Check the example app for implementation details
- Review the API documentation
- Open an issue on our GitHub repository
