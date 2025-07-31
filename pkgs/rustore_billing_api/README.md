# RuStore Billing API

A Flutter plugin for integrating RuStore billing functionality into your Flutter applications. This plugin provides a comprehensive interface to the RuStore billing SDK, allowing you to handle in-app purchases, subscriptions, and payment flows.

## Features

- ✅ Initialize RuStore billing client
- ✅ Check RuStore installation status
- ✅ Check purchase availability
- ✅ Retrieve product information
- ✅ Get existing purchases
- ✅ Start purchase flows
- ✅ Confirm purchases
- ✅ Delete purchases
- ✅ Handle deep link intents
- ✅ Dynamic theme switching (Light/Dark)
- ✅ External payment logging
- ✅ Comprehensive error handling
- ✅ Stream-based purchase result notifications

## Installation

Add this dependency to your `pubspec.yaml`:

```yaml
dependencies:
  rustore_billing_api: ^1.0.0
```

## Setup

### 1. Android Configuration

Add the RuStore repository to your `android/build.gradle`:

```gradle
allprojects {
    repositories {
        maven { url = uri("https://artifactory-external.vkpartner.ru/artifactory/maven") }
    }
}
```

Add the RuStore BOM dependency to your `android/app/build.gradle`:

```gradle
dependencies {
    implementation(platform("ru.rustore.sdk:bom:2025.06.01"))
    implementation("ru.rustore.sdk:billingclient")
}
```

### 2. AndroidManifest.xml Configuration

Add deep link handling to your `android/app/src/main/AndroidManifest.xml`:

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTask">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="yourappscheme" />
    </intent-filter>
</activity>
```

### 3. Activity Configuration

Update your main activity to handle deep links:

```kotlin
class MainActivity: FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            // Handle deep link intent
            rustoreBillingClient.onNewIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        // Handle deep link intent
        rustoreBillingClient.onNewIntent(intent)
    }
}
```

## Usage

### 1. Initialize the Billing Client

```dart
import 'package:rustore_billing_api/rustore_billing_api.dart';

final client = RustoreBillingClient.instance;

await client.initialize(
  RustoreBillingConfig(
    consoleApplicationId: 'your_app_id_here',
    deeplinkScheme: 'yourappscheme',
    debugLogs: true,
    theme: RustoreBillingTheme.light,
    enableLogging: true,
  ),
);
```

### 2. Check RuStore Installation and Availability

```dart
// Check if RuStore is installed
final isAuthorized = await client.isRustoreUserAuthorized();

// Check if purchases are available
final availability = await client.checkPurchasesAvailability();
switch (availability.resultType) {
  case RustorePurchaseAvailabilityType.available:
    print('Purchases are available');
    break;
  case RustorePurchaseAvailabilityType.unavailable:
    print('Purchases unavailable: ${availability.cause?.message}');
    break;
  case RustorePurchaseAvailabilityType.unknown:
    print('Purchase availability unknown');
    break;
}
```

### 3. Load Products

```dart
final products = await client.getProducts([
  'product_id_1',
  'product_id_2',
  'subscription_id_1',
]);

for (final product in products) {
  print('Product: ${product.title} - ${product.priceLabel}');
}
```

### 4. Load Purchases

```dart
final purchases = await client.getPurchases();

for (final purchase in purchases) {
  print('Purchase: ${purchase.productId} - ${purchase.purchaseState}');
}
```

### 5. Start Purchase Flow

```dart
final result = await client.purchaseProduct(
  'product_id_1',
  developerPayload: 'custom_payload_${DateTime.now().millisecondsSinceEpoch}',
);

switch (result.resultType) {
  case RustorePaymentResultType.success:
    print('Purchase successful: ${result.purchaseId}');
    // Confirm the purchase
    await client.confirmPurchase(result.purchaseId!);
    break;
  case RustorePaymentResultType.cancelled:
    print('Purchase cancelled');
    break;
  case RustorePaymentResultType.failure:
    print('Purchase failed: ${result.errorMessage}');
    break;
  case RustorePaymentResultType.invalid_payment_state:
    print('Invalid payment state: ${result.errorMessage}');
    break;
}
```

### 6. Listen to Purchase Results

```dart
// Listen to purchase results
client.purchaseResults.listen((result) {
  print('Purchase result: ${result.resultType}');
});

// Listen to errors
client.errors.listen((error) {
  print('Error: ${error.message} (${error.code})');
});
```

### 7. Theme Management

```dart
// Change theme dynamically
await client.setTheme(RustoreBillingTheme.dark);
```

### 8. Handle Deep Links

In your main activity, call `onNewIntent` when receiving deep links:

```dart
// This should be called from your Android activity's onNewIntent method
client.onNewIntent(intentData);
```

## API Reference

### RustoreBillingConfig

Configuration for the RuStore billing client.

```dart
class RustoreBillingConfig {
  final String consoleApplicationId;  // Your app ID from RuStore console
  final String deeplinkScheme;        // Deep link scheme for payment flows
  final bool debugLogs;               // Enable debug logging
  final RustoreBillingTheme theme;    // Billing client theme
  final bool enableLogging;           // Enable external payment logging
}
```

### RustoreProduct

Represents a product available for purchase.

```dart
class RustoreProduct {
  final String productId;
  final String productType;
  final String? title;
  final String? description;
  final int? price;
  final String? priceLabel;
  final String? currency;
  final String? language;
}
```

### RustorePurchase

Represents a purchase made by the user.

```dart
class RustorePurchase {
  final String? purchaseId;
  final String? productId;
  final String? invoiceId;
  final String? description;
  final String? language;
  final String? purchaseTime;
  final String? orderId;
  final String? amountLabel;
  final int? amount;
  final String? currency;
  final int? quantity;
  final RustorePurchaseState? purchaseState;
  final String? developerPayload;
}
```

### RustorePaymentResult

Result of a purchase operation.

```dart
class RustorePaymentResult {
  final RustorePaymentResultType resultType;
  final String? purchaseId;
  final String? errorCode;
  final String? errorMessage;
}
```

### Error Handling

The plugin provides comprehensive error handling with specific error types:

```dart
enum RustoreExceptionType {
  notInstalled,        // RuStore is not installed
  outdated,           // RuStore version is outdated
  userUnauthorized,   // User is not authorized
  requestLimitReached, // Request limit reached
  reviewExists,       // Review already exists
  invalidReviewInfo,  // Invalid review information
  general,            // General error
}
```

## Error Codes

The plugin handles various error codes from the RuStore SDK:

| HTTP Code | Error Code | Description                              |
| --------- | ---------- | ---------------------------------------- |
| 400       | 40001      | Incorrect request parameters             |
| 400       | 40003      | App not found                            |
| 400       | 40004      | App status: inactive                     |
| 400       | 40005      | Product not found                        |
| 400       | 40006      | Product status: inactive                 |
| 400       | 40007      | Invalid product type                     |
| 400       | 40008      | Order with this order_id already exists  |
| 400       | 40009      | Active order exists for this product     |
| 400       | 40010      | Order in paid state needs to be consumed |
| 400       | 40011      | Non-consumable product already purchased |
| 400       | 40012      | Subscription already purchased           |
| 400       | 40013      | Service data not received                |
| 400       | 40014      | Mandatory attribute missing              |
| 400       | 40015      | Failed to change order status            |
| 400       | 40016      | Quantity > 1 for non-consumable product  |
| 400       | 40017      | Product deleted                          |
| 400       | 40018      | Cannot consume products with this type   |
| 401       | 40101      | Invalid token                            |
| 401       | 40102      | Token lifetime expired                   |
| 403       | 40301      | Access denied                            |
| 403       | 40302      | Method not allowed                       |
| 403       | 40303      | App ID doesn't match token               |
| 403       | 40305      | Incorrect token type                     |
| 404       | 40401      | Not found                                |
| 408       | 40801      | Notification timeout expired             |
| 500       | 50\*\*\*   | Payment service internal error           |

## Best Practices

1. **Always check RuStore installation** before attempting billing operations
2. **Verify purchase availability** to ensure the device supports purchases
3. **Handle all purchase result types** including cancellations and failures
4. **Confirm purchases** after receiving successful payment results
5. **Use developer payloads** for tracking and verification
6. **Implement proper error handling** for all billing operations
7. **Listen to purchase result streams** for real-time updates
8. **Test with debug logging enabled** during development

## Troubleshooting

### Common Issues

1. **"Billing client not initialized"**

   - Ensure you call `initialize()` before any other operations
   - Check that your `consoleApplicationId` is correct

2. **"Purchases unavailable"**

   - Verify RuStore is installed on the device
   - Check that your app is properly configured in RuStore Console
   - Ensure the device supports purchases

3. **Deep link issues**

   - Verify the scheme in `AndroidManifest.xml` matches your config
   - Ensure your activity handles `onNewIntent` properly

4. **Product not found**
   - Check that product IDs exist in RuStore Console
   - Verify product status is active
   - Ensure product type is supported

### Debug Logging

Enable debug logging to troubleshoot issues:

```dart
await client.initialize(
  RustoreBillingConfig(
    consoleApplicationId: 'your_app_id',
    deeplinkScheme: 'yourappscheme',
    debugLogs: true,  // Enable debug logs
    enableLogging: true,  // Enable external logging
  ),
);
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

For issues and questions:

- Check the [RuStore documentation](https://www.rustore.ru/help/en/sdk/payments/kotlin-java/9-1-0)
- Open an issue on GitHub
- Contact the maintainers
