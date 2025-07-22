# XSoulSpace Monetization Foundation

A comprehensive Flutter monetization framework that provides a unified interface for ads, subscriptions, and purchases across multiple platforms.

## 🎯 Purpose

This package serves as the foundation for implementing monetization strategies in Flutter apps, abstracting platform-specific complexities behind clean, testable interfaces.

## 🏗️ Architecture Overview

### Core Patterns

- **Command Pattern**: Business logic encapsulated in immutable command objects
- **Resource Pattern**: Reactive state management with ChangeNotifier
- **Provider Pattern**: Platform-specific implementations behind common interfaces
- **Strategy Pattern**: Different monetization types (subscription, ads, free)

### Key Components

```
lib/
├── ads/                    # Ad management
├── commands/              # Business logic commands
├── models/                # Core enums and types
├── noop_providers/        # Testing implementations
├── resources/             # State management
├── widgets/               # UI components
└── purchase_initializer.dart  # Main orchestrator
```

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

### 3. Command Pattern

Commands encapsulate business logic:

- `SubscribeCommand`: Handle subscription purchases
- `ConfirmPurchaseCommand`: Complete purchase verification
- `RestorePurchasesCommand`: Restore previous purchases
- `LoadSubscriptionsCommand`: Load available products

## 🚀 Quick Start

```dart
// 1. Initialize resources
final monetizationStatus = MonetizationStatusResource();
final subscriptionStatus = SubscriptionStatusResource();
final activeSubscription = ActiveSubscriptionResource();
final availableSubscriptions = AvailableSubscriptionsResource();

// 2. Create commands
final confirmPurchase = ConfirmPurchaseCommand(
  purchaseProvider: yourProvider,
  activeSubscriptionResource: activeSubscription,
  subscriptionStatusResource: subscriptionStatus,
);

// 3. Initialize system
final initializer = PurchaseInitializer(
  monetizationStatusResource: monetizationStatus,
  purchaseProvider: yourProvider,
  restorePurchasesCommand: RestorePurchasesCommand(...),
  handlePurchaseUpdateCommand: HandlePurchaseUpdateCommand(...),
  loadSubscriptionsCommand: LoadSubscriptionsCommand(...),
);

await initializer.init();
```

## 📱 Platform Support

- **Google Play**: Via `xsoulspace_monetization_google_apple`
- **App Store**: Via `xsoulspace_monetization_google_apple`
- **RuStore**: Via `xsoulspace_monetization_rustore`
- **Huawei**: Via `xsoulspace_monetization_huawai`
- **Yandex Ads**: Via `xsoulspace_monetization_ads_yandex`

## 🧪 Testing

Use `NoopAdProvider` and `NoopPurchaseProvider` for testing without real transactions.

## 🔄 State Flow

```
App Start → PurchaseInitializer.init()
    ↓
Load Subscriptions → Restore Purchases → Listen for Updates
    ↓
State Resources Updated → UI Reacts
```

## 🎨 UI Components

- `SubscriptionScreen`: Display and manage subscriptions
- `PurchaseScreen`: One-time purchase options
- `PurchaseGuardScreen`: Protect premium features
- `PricingScreen`: Show pricing structure
- `AdFreeScreen`: Ad removal options
- `FamilyPlanScreen`: Family/team plans

## 🔐 Security

- Purchase verification through platform providers
- Secure credential storage via OAuth integration
- Platform-specific security measures

## 📚 Related Packages

- `xsoulspace_monetization_interface`: Core interfaces
- `xsoulspace_monetization_ads_interface`: Ad provider interface
- Platform-specific implementations in separate packages
