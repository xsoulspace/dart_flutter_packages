import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// The store name a binding composes — an open set of lowercase
/// identifiers (`google-play`, `rustore`, `appgallery`, `snapstore`, …),
/// no enum, no registry (oka ADR-0055/0056 lineage).
///
/// The name is a plain [String] by law: monetization and oka are separate
/// ecosystems and join on the store-name contract (oka bakes
/// `OKA_STORE=<name>` into a delivery build; the app boot verifies its
/// binding carries the same name), not on a shared type. Well-known names
/// live beside the store packages that own them; a store this package has
/// never heard of is a new string value, never a PR.
const storeNameNoop = 'noop';

/// The store binding a monetization-aware app composes.
///
/// A binding names the store openly ([key], no enum) and constructs the
/// purchase provider compiled for it. The hand-typed binding file imports
/// exactly one backend package, and the app's per-store entrypoint imports
/// exactly one binding — so only that backend ships in the AOT kernel.
///
/// ```dart
/// // lib/store/bindings/rustore.dart (Last Answer)
/// final class RuStoreBinding implements MonetizationStoreBinding {
///   const RuStoreBinding();
///   @override
///   String get key => 'rustore';
///   @override
///   PurchaseProvider? Function() get purchaseProviderFactory =>
///       () => RustorePurchaseProvider(
///             consoleApplicationId: '2045332927',
///             deeplinkScheme: 'dev.xsoulspace.lastanswer',
///             productTypeChecker: MonetizationProducts.productTypeChecker,
///           );
/// }
/// ```
///
/// A `null` factory (or a factory returning `null`) means "this build has
/// no purchase backend" — the composition root falls back to
/// `NoopPurchaseProvider` (`NoopMonetizationStoreBinding` below).
abstract interface class MonetizationStoreBinding {
  /// The store name this binding composes (lowercase identifier; see
  /// [storeNameNoop] for the store-neutral value).
  String get key;

  /// Constructs this store's purchase provider, or null when the build
  /// ships no purchase backend for this store.
  PurchaseProvider? Function() get purchaseProviderFactory;
}

/// The store-neutral monetization binding: no store, no provider — the
/// dev/website/snap posture.
class NoopMonetizationStoreBinding implements MonetizationStoreBinding {
  /// Const constructor; defaults to the shared `noop` name.
  const NoopMonetizationStoreBinding();

  @override
  String get key => storeNameNoop;

  @override
  PurchaseProvider? Function() get purchaseProviderFactory => () => null;
}
