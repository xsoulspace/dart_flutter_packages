/// # XSoulSpace Monetization Foundation
///
/// A comprehensive Flutter monetization framework that provides unified interfaces
/// for ads, subscriptions, and purchases across multiple platforms.
///
/// ## 🎯 Core Purpose
///
/// This package abstracts platform-specific monetization complexities behind clean,
/// testable interfaces. It implements the Command pattern for business logic,
/// Resource pattern for state management, and Provider pattern for platform implementations.
///
/// ## 🏗️ Architecture
///
/// ### Key Components:
/// - **Ads**: Ad management with platform-agnostic interface
/// - **Commands**: Immutable business logic objects for purchase operations
/// - **Models**: Core enums and types for monetization state
/// - **Resources**: Reactive state management with ChangeNotifier
/// - **Widgets**: headless, slot-based compositional views — state flows in
///   through properties, actions flow out through callbacks, and every
///   visual is a caller-supplied builder (no Material UI)
/// - **Noop Providers**: Testing implementations without real transactions
///
/// ### State Flow:
/// ```
/// App Start → PurchaseInitializer.init()
///     ↓
/// Load Subscriptions → Restore Purchases → Listen for Updates
///     ↓
/// State Resources Updated → UI Reacts
/// ```
///
/// ## 🚀 Quick Usage
///
/// ```dart
/// // Initialize resources
/// final monetizationStatus = MonetizationStatusResource();
/// final subscriptionStatus = SubscriptionStatusResource();
///
/// // Create commands
/// final confirmPurchase = ConfirmPurchaseCommand(
///   purchaseProvider: yourProvider,
///   activeSubscriptionResource: activeSubscription,
///   subscriptionStatusResource: subscriptionStatus,
/// );
///
/// // Initialize system
/// final initializer = PurchaseInitializer(...);
/// await initializer.init();
/// ```
///
/// ## 📱 Platform Support
///
/// - Google Play & App Store via `xsoulspace_monetization_google_apple`
/// - RuStore via `xsoulspace_monetization_rustore`
/// - Huawei via `xsoulspace_monetization_huawei`
/// - Yandex Ads via `xsoulspace_monetization_ads_yandex`
///
/// ## 🧪 Testing
///
/// Use `NoopAdProvider` and `NoopPurchaseProvider` for testing without real transactions.
///
/// ## 🔐 Security
///
/// - Purchase verification through platform providers
/// - Secure credential storage via OAuth integration
/// - Platform-specific security measures
library;

// Ad Management
export 'src/ads/ad_manager.dart';
// Business Logic Commands
export 'src/commands/commands.dart';
// Local API
export 'src/local_api/local_api.dart';
// Core Models and Types
export 'src/models/models.dart';
// Main Orchestrator
export 'src/monetization_foundation.dart';
export 'src/store_binding.dart';
// Testing Implementations
export 'src/noop_providers/noop_providers.dart';
// State Management Resources
export 'src/resources/resources.dart';
// UI Components
export 'src/widgets/widgets.dart';
