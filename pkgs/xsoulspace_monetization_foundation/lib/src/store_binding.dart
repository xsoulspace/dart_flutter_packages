import 'package:oka_store/oka_store.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// The store binding a monetization-aware app composes — monetization
/// extends oka's store contract, never the reverse (store identity is not
/// about monetization; ADR-0055 dependency law: monetization → oka).
///
/// A binding names the store openly ([StoreKey], no enum) and constructs
/// the purchase provider compiled for it. The hand-typed binding file
/// imports exactly one backend package, and the app's per-store
/// entrypoint imports exactly one binding — so only that backend ships
/// in the AOT kernel.
///
/// ```dart
/// // lib/store/bindings/rustore.dart (Last Answer)
/// final class RuStoreBinding implements MonetizationStoreBinding {
///   const RuStoreBinding();
///   @override
///   StoreKey get key => storeKeyRuStore;
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
/// `NoopPurchaseProvider` (`noopBinding` below).
abstract interface class MonetizationStoreBinding implements StoreBinding {
  /// Constructs this store's purchase provider, or null when the build
  /// ships no purchase backend for this store.
  PurchaseProvider? Function() get purchaseProviderFactory;
}

/// The store-neutral monetization binding: no key, no provider — the
/// dev/website/snap posture.
class NoopMonetizationStoreBinding implements MonetizationStoreBinding {
  /// Const constructor; defaults to the shared `noop` key.
  const NoopMonetizationStoreBinding();

  @override
  StoreKey get key => storeKeyNoop;

  @override
  PurchaseProvider? Function() get purchaseProviderFactory => () => null;
}
