import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// Base class for the state of a purchasable products fetch.
///
/// Views switch over this state and delegate every visual to
/// caller-supplied builders, so the package ships no Material UI.
sealed class PurchaseProductsState {
  const PurchaseProductsState();
}

/// State while product details are being fetched.
class ProductsLoading extends PurchaseProductsState {
  /// Creates the loading state.
  const ProductsLoading();
}

/// State when fetching product details failed.
class ProductsError extends PurchaseProductsState {
  /// Creates an error state carrying [error].
  const ProductsError(this.error);

  /// The error thrown while fetching product details.
  final Object error;
}

/// State when product details are available.
class ProductsReady extends PurchaseProductsState {
  /// Creates a ready state carrying [products].
  const ProductsReady(this.products);

  /// The fetched product details.
  final List<PurchaseProductDetailsModel> products;
}
