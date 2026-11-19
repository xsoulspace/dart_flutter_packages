# XSoulSpace Monetization Foundation

Unified Flutter monetization framework for ads, subscriptions, and purchases across multiple platforms.

## 🎯 Purpose

This package serves as the foundation for implementing monetization strategies in Flutter apps, abstracting platform-specific complexities behind clean, testable interfaces.

## 🏗️ Architecture Overview

### Core Patterns

- **Command Pattern**: Business logic encapsulated in immutable command objects
- **Resource Pattern**: Reactive state management with ChangeNotifier
- **Purchase Provider Pattern**: Platform-specific implementations behind common interfaces
- **Strategy Pattern**: Different monetization types (subscription, ads, free)

## 🔧 Core Concepts

### 1. Monetization Types

- **Subscription**: Recurring payments for premium features
- **Ads**: Ad-supported model with premium upgrade option
- **Free**: All features available without payment

### 2. State Management

- `MonetizationStatusResource`: Overall system status
- `SubscriptionStatusResource`: User subscription state
- `ActiveSubscriptionResource`: Current subscription details
- `AvailableSubscriptionsResource`: Available products

## 📦 Installation

```yaml
dependencies:
  xsoulspace_monetization_foundation: ^1.0.0
```

## 🚀 Quick Start

```dart
// 1. Create resources
final resources = (
  status: MonetizationStatusResource(),
  type: MonetizationTypeResource(MonetizationType.subscription),
  activeSubscription: ActiveSubscriptionResource(),
  subscriptionStatus: SubscriptionStatusResource(),
  availableSubscriptions: AvailableSubscriptionsResource(),
);

// 2. Initialize foundation
final foundation = MonetizationFoundation(
  resources: resources,
  purchaseProvider: yourPlatformProvider, // Google Play, App Store, etc.
);

// 2.1. Initialize local api
await foundation.initLocal();

// 2.2. Start monetization system with await
await foundation.init(productIds: ['premium_monthly', 'premium_yearly']);

// 2.3. or don't await
unawaited(foundation.init());

// 3. Subscribe to a product
final success = await foundation.subscribe(productDetails);
```

## 🏗️ Core Concepts

- **Command Pattern**: Business logic in immutable commands (`SubscribeCommand`, `ConfirmPurchaseCommand`)
- **Resource Pattern**: Reactive state management with `ChangeNotifier` (subscription status, available products)
- **Provider Pattern**: Platform-specific implementations behind common interfaces

## 🏛️ Architectural Patterns

### Command Pattern

```dart
// Immutable business logic objects
final subscribeCommand = SubscribeCommand(
  purchaseProvider: provider,
  subscriptionStatusResource: statusResource,
  confirmPurchaseCommand: confirmCommand,
);
await subscribeCommand.execute(productDetails);
```

### Resource Pattern

```dart
// Reactive state management
final statusResource = SubscriptionStatusResource();
statusResource.addListener(() {
  // UI updates automatically
  if (statusResource.isSubscribed) {
    // Show premium features
  }
});
```

### Purchase Provider Pattern

```dart
// Platform-agnostic interface
abstract class PurchaseProvider {
  Future<PurchaseResultModel> subscribe(ProductDetails details);
  Future<List<ProductDetails>> getSubscriptions(List<String> ids);
}

// Use platform-specific implementations
final provider = GooglePlayPurchaseProvider();
```

## 📱 Platform Support

| Platform                | Package                                | Status |
| ----------------------- | -------------------------------------- | ------ |
| Google Play & App Store | `xsoulspace_monetization_google_apple` | 🚧     |
| RuStore                 | `xsoulspace_monetization_rustore`      | ✅     |
| Huawei                  | `xsoulspace_monetization_huawei`       | 🚧     |

## 🧪 Testing

Use noop providers for testing without real transactions:

```dart
final testProvider = NoopPurchaseProvider();
final testAdProvider = NoopAdProvider();
```

## 🏛️ Architecture

```
lib/
├── ads/           # Ad management (AdManager)
├── commands/      # Business logic (SubscribeCommand, etc.)
├── models/        # Core types (MonetizationStatus, MonetizationType)
├── resources/     # State management (ChangeNotifier-based)
├── widgets/       # Headless slot-based views (PurchaseListView, PurchaseGate, etc.)
└── noop_providers/ # Testing implementations
```

## 🔗 Related Packages

- `xsoulspace_monetization_interface` - Core interfaces
- `xsoulspace_monetization_ads_interface` - Ad provider interface
- Platform-specific implementations in separate packages
