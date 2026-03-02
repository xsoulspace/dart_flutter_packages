# rustore_billing_api

Flutter plugin for RuStore Billing/Pay SDK integration (Android).

This release aligns the plugin API with RuStore Kotlin/Java `10.1.0` purchase
flows:

- one-step and two-step purchases
- purchase availability + authorization status
- filtered purchase loading
- purchase updates stream with typed result/error payloads

## Installation

```yaml
dependencies:
  rustore_billing_api: ^1.0.0
```

## Android setup

Add RuStore repository to your Android build repositories.

Add RuStore Billing dependency:

```kotlin
dependencies {
    implementation("ru.rustore.sdk:billingclient:10.1.0")
}
```

Add deep link scheme in your `AndroidManifest.xml` activity:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="yourappscheme" />
</intent-filter>
```

## Quick start

```dart
import 'package:rustore_billing_api/rustore_billing_api.dart';

final client = RustoreBillingClient.instance;

await client.initialize(
  RustoreBillingConfig(
    consoleApplicationId: 'your_app_id',
    deeplinkScheme: 'yourappscheme',
    debugLogs: true,
  ),
);

final authorized = await client.getUserAuthorizationStatus();
final availability = await client.getPurchaseAvailability();

final products = await client.getProducts(<String>['product_1']);
```

## One-step purchase

```dart
final result = await client.purchase(
  RustoreProductPurchaseParams(
    productId: 'product_1',
    quantity: 1,
    developerPayload: 'payload',
  ),
  preferredPurchaseType: RustorePreferredPurchaseType.oneStep,
);
```

## Two-step purchase

```dart
final result = await client.purchaseTwoStep(
  RustoreProductPurchaseParams(productId: 'consumable_1'),
);

final purchaseId = result.purchase?.purchaseId;
if (purchaseId != null && purchaseId.isNotEmpty) {
  await client.confirmTwoStepPurchase(purchaseId);
  // or: await client.cancelTwoStepPurchase(purchaseId);
}
```

## Purchases API

```dart
final all = await client.getPurchases();

final filtered = await client.getPurchases(
  filter: RustorePurchaseFilter(
    productType: RustoreProductType.subscription,
    purchaseStatus: RustorePurchaseStatus.active,
  ),
);

final single = await client.getPurchase('purchase_id');
```

## Updates stream

```dart
client.updatesStream.listen((event) {
  if (event.purchaseResult case final result?) {
    // typed purchase result
  }
  if (event.error case final error?) {
    // typed purchase error
  }
});
```

## Breaking migration (`0.8.x` -> `1.0.0`)

| 0.8.x | 1.0.0 |
|---|---|
| `checkPurchasesAvailability()` | `getPurchaseAvailability()` |
| `isRustoreUserAuthorized()` | `getUserAuthorizationStatus()` |
| `purchaseProduct(...)` | `purchase(...)` |
| `confirmPurchase(...)` | `confirmTwoStepPurchase(...)` |
| `deletePurchase(...)` | `cancelTwoStepPurchase(...)` |
| `getPurchases()` | `getPurchases(filter: ...)` + `getPurchase(id)` |
| `setTheme(...)` | removed (`sdkTheme` passed per purchase call) |
| `onNewIntent(...)` | removed from Dart API (handled natively) |
